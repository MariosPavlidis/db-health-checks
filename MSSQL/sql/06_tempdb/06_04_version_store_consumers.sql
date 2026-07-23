-- =============================================================================
-- Health Check: Ch 06 TempDB — 6.4 Version Store Consumers
-- Min SQL version: SQL Server 2016
--
-- Result sets:
--   1. RCSI/SNAPSHOT configuration and tempdb version-store space by database
--   2. Active transactions that generate or can retain row versions
--   3. Session/transaction detail for the largest active versioning consumers
--
-- Notes:
--   sys.dm_tran_version_store_space_usage is available in SQL Server 2016 SP2+.
--   The DMV is efficient because it returns aggregate usage without scanning
--   individual version records. Older SQL Server 2016 builds return a note row.
-- =============================================================================
SET NOCOUNT ON;

IF TRY_CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT
        'VERSION_GUARD' AS ResultSetName,
        'Requires SQL Server 2016 or later.' AS Note;
    RETURN;
END;

-- ── 1. Database row-versioning configuration and version-store footprint ─────
IF OBJECT_ID(N'sys.dm_tran_version_store_space_usage') IS NOT NULL
BEGIN
    SELECT
        'DATABASE_VERSIONING_MAP'                         AS ResultSetName,
        d.database_id                                    AS DatabaseId,
        d.name                                           AS DatabaseName,
        d.state_desc                                     AS DatabaseState,
        d.is_read_committed_snapshot_on                  AS IsRCSIEnabled,
        d.snapshot_isolation_state_desc                  AS SnapshotIsolationState,
        CAST(vsu.reserved_page_count * 8.0 / 1024.0
             AS DECIMAL(18,2))                           AS VersionStoreMB,
        CASE
            WHEN d.is_read_committed_snapshot_on = 1
              OR d.snapshot_isolation_state IN (1, 3) THEN 1 ELSE 0
        END                                              AS flag_row_versioning_enabled,
        CASE
            WHEN vsu.reserved_page_count * 8.0 / 1024.0 >= 1024 THEN 1 ELSE 0
        END                                              AS flag_version_store_over_1gb
    FROM sys.databases AS d
    LEFT JOIN sys.dm_tran_version_store_space_usage AS vsu
        ON vsu.database_id = d.database_id
    WHERE d.database_id <> 2
    ORDER BY VersionStoreMB DESC, d.name;
END
ELSE
BEGIN
    SELECT
        'DATABASE_VERSIONING_MAP' AS ResultSetName,
        'sys.dm_tran_version_store_space_usage requires SQL Server 2016 SP2 or later.' AS Note;
END;

-- ── 2. Active transactions capable of retaining row versions ─────────────────
SELECT
    'ACTIVE_SNAPSHOT_TRANSACTIONS'                       AS ResultSetName,
    ast.session_id                                      AS SessionId,
    es.login_name                                       AS LoginName,
    es.host_name                                        AS HostName,
    es.program_name                                     AS ProgramName,
    er.database_id                                      AS RequestDatabaseId,
    DB_NAME(er.database_id)                             AS RequestDatabaseName,
    ast.transaction_id                                  AS TransactionId,
    ast.transaction_sequence_num                        AS TransactionSequenceNumber,
    ast.first_snapshot_sequence_num                     AS FirstSnapshotSequenceNumber,
    ast.commit_sequence_num                             AS CommitSequenceNumber,
    ast.is_snapshot                                     AS IsSnapshotTransaction,
    ast.elapsed_time_seconds                            AS ElapsedTimeSeconds,
    CAST(ast.elapsed_time_seconds / 60.0 AS DECIMAL(18,1))
                                                         AS ElapsedTimeMinutes,
    ast.max_version_chain_traversed                     AS MaxVersionChainTraversed,
    ast.average_version_chain_traversed                 AS AverageVersionChainTraversed,
    er.status                                           AS RequestStatus,
    er.command                                          AS RequestCommand,
    er.wait_type                                        AS WaitType,
    er.wait_time                                        AS WaitTimeMs,
    er.blocking_session_id                              AS BlockingSessionId,
    SUBSTRING(
        st.text,
        (COALESCE(er.statement_start_offset, 0) / 2) + 1,
        ((CASE COALESCE(er.statement_end_offset, -1)
              WHEN -1 THEN DATALENGTH(st.text)
              ELSE er.statement_end_offset
          END - COALESCE(er.statement_start_offset, 0)) / 2) + 1
    )                                                   AS CurrentStatement,
    CASE WHEN ast.elapsed_time_seconds >= 900 THEN 1 ELSE 0 END
                                                         AS flag_snapshot_over_15min,
    CASE WHEN ast.elapsed_time_seconds >= 3600 THEN 1 ELSE 0 END
                                                         AS flag_snapshot_over_60min
FROM sys.dm_tran_active_snapshot_database_transactions AS ast
LEFT JOIN sys.dm_exec_sessions AS es
    ON es.session_id = ast.session_id
LEFT JOIN sys.dm_exec_requests AS er
    ON er.session_id = ast.session_id
OUTER APPLY sys.dm_exec_sql_text(er.sql_handle) AS st
ORDER BY ast.elapsed_time_seconds DESC, ast.session_id;

-- ── 3. Active session/database transactions and log-generation proxy ─────────
-- database_transaction_log_bytes_used measures current transaction log usage.
-- It does not equal row-version bytes, but identifies active writers that can
-- generate versions while snapshot readers retain the cleanup horizon.
SELECT TOP (50)
    'ACTIVE_VERSIONING_CONSUMERS'                        AS ResultSetName,
    st.session_id                                       AS SessionId,
    es.login_name                                       AS LoginName,
    es.host_name                                        AS HostName,
    es.program_name                                     AS ProgramName,
    dt.database_id                                      AS DatabaseId,
    DB_NAME(dt.database_id)                             AS DatabaseName,
    at.transaction_id                                   AS TransactionId,
    at.transaction_begin_time                           AS TransactionBeginTime,
    DATEDIFF(SECOND, at.transaction_begin_time, SYSDATETIME())
                                                         AS TransactionAgeSeconds,
    dt.database_transaction_type                        AS DatabaseTransactionType,
    dt.database_transaction_state                       AS DatabaseTransactionState,
    dt.database_transaction_log_record_count            AS LogRecordCount,
    dt.database_transaction_log_bytes_used              AS LogBytesUsed,
    dt.database_transaction_log_bytes_reserved          AS LogBytesReserved,
    ast.elapsed_time_seconds                            AS SnapshotElapsedTimeSeconds,
    ast.max_version_chain_traversed                     AS MaxVersionChainTraversed,
    er.status                                           AS RequestStatus,
    er.command                                          AS RequestCommand,
    er.wait_type                                        AS WaitType,
    er.blocking_session_id                              AS BlockingSessionId,
    ib.event_info                                       AS LastSubmittedCommand,
    CASE
        WHEN ast.elapsed_time_seconds >= 900 THEN 1 ELSE 0
    END                                                 AS flag_retaining_versions,
    CASE
        WHEN dt.database_transaction_log_bytes_used >= 1073741824 THEN 1 ELSE 0
    END                                                 AS flag_active_writer_over_1gb_log
FROM sys.dm_tran_session_transactions AS st
JOIN sys.dm_tran_active_transactions AS at
    ON at.transaction_id = st.transaction_id
JOIN sys.dm_tran_database_transactions AS dt
    ON dt.transaction_id = st.transaction_id
LEFT JOIN sys.dm_tran_active_snapshot_database_transactions AS ast
    ON ast.transaction_id = st.transaction_id
LEFT JOIN sys.dm_exec_sessions AS es
    ON es.session_id = st.session_id
LEFT JOIN sys.dm_exec_requests AS er
    ON er.session_id = st.session_id
OUTER APPLY sys.dm_exec_input_buffer(st.session_id, NULL) AS ib
WHERE st.session_id > 50
ORDER BY
    COALESCE(ast.elapsed_time_seconds, 0) DESC,
    dt.database_transaction_log_bytes_used DESC;
