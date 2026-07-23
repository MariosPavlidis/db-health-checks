-- =============================================================================
-- Health Check: Ch 06 TempDB — 6.7 ADR Persistent Version Store
-- Min SQL version: SQL Server 2016
-- ADR/PVS detail: SQL Server 2019+
--
-- Result sets:
--   1. ADR configuration for every database
--   2. PVS size and cleaner state for ADR-enabled databases
--   3. Old active transactions that can delay PVS cleanup
-- =============================================================================
SET NOCOUNT ON;

IF TRY_CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'VERSION_GUARD' AS ResultSetName,
           'Requires SQL Server 2016 or later.' AS Note;
    RETURN;
END;

IF TRY_CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 15
BEGIN
    SELECT
        'ADR_DATABASE_STATE' AS ResultSetName,
        d.database_id       AS DatabaseId,
        d.name              AS DatabaseName,
        d.state_desc        AS DatabaseState,
        CAST(0 AS BIT)      AS IsAcceleratedDatabaseRecoveryOn,
        'ADR and the persistent version store require SQL Server 2019 or later.' AS Note
    FROM sys.databases AS d
    ORDER BY d.name;
    RETURN;
END;

-- References to SQL Server 2019+ columns are isolated in dynamic SQL so this
-- file still parses and exits cleanly on SQL Server 2016/2017.
DECLARE @Sql NVARCHAR(MAX) = N'
-- ── 1. ADR configuration ─────────────────────────────────────────────────────
SELECT
    ''ADR_DATABASE_STATE''                               AS ResultSetName,
    d.database_id                                       AS DatabaseId,
    d.name                                              AS DatabaseName,
    d.state_desc                                        AS DatabaseState,
    d.is_accelerated_database_recovery_on               AS IsAcceleratedDatabaseRecoveryOn,
    d.recovery_model_desc                               AS RecoveryModel,
    d.log_reuse_wait_desc                               AS LogReuseWait
FROM sys.databases AS d
ORDER BY d.is_accelerated_database_recovery_on DESC, d.name;

-- ── 2. Persistent Version Store size and cleaner state ───────────────────────
SELECT
    ''ADR_PVS_HEALTH''                                  AS ResultSetName,
    pvs.database_id                                    AS DatabaseId,
    DB_NAME(pvs.database_id)                           AS DatabaseName,
    pvs.pvs_filegroup_id                               AS PvsFilegroupId,
    pvs.persistent_version_store_size_kb               AS PersistentVersionStoreSizeKB,
    CAST(pvs.persistent_version_store_size_kb / 1024.0
         AS DECIMAL(18,2))                             AS PersistentVersionStoreSizeMB,
    pvs.online_index_version_store_size_kb             AS OnlineIndexVersionStoreSizeKB,
    CAST(pvs.online_index_version_store_size_kb / 1024.0
         AS DECIMAL(18,2))                             AS OnlineIndexVersionStoreSizeMB,
    pvs.current_aborted_transaction_count              AS CurrentAbortedTransactionCount,
    pvs.oldest_active_transaction_id                   AS OldestActiveTransactionId,
    pvs.oldest_aborted_transaction_id                  AS OldestAbortedTransactionId,
    pvs.min_transaction_timestamp                      AS MinTransactionTimestamp,
    pvs.online_index_min_transaction_timestamp         AS OnlineIndexMinTransactionTimestamp,
    pvs.secondary_low_water_mark                       AS SecondaryLowWaterMark,
    pvs.offrow_version_cleaner_start_time              AS OffRowCleanerStartTime,
    pvs.offrow_version_cleaner_end_time                AS OffRowCleanerEndTime,
    pvs.aborted_version_cleaner_start_time             AS CleanerStartTime,
    pvs.aborted_version_cleaner_end_time               AS CleanerEndTime,
    CASE
        WHEN pvs.persistent_version_store_size_kb >= 1048576 THEN 1 ELSE 0
    END                                                AS flag_pvs_over_1gb,
    CASE
        WHEN pvs.offrow_version_cleaner_start_time IS NOT NULL
         AND pvs.offrow_version_cleaner_end_time IS NULL
         AND DATEDIFF(MINUTE, pvs.offrow_version_cleaner_start_time, SYSDATETIME()) >= 60
            THEN 1 ELSE 0
    END                                                AS flag_offrow_cleaner_running_over_60min,
    CASE
        WHEN pvs.current_aborted_transaction_count > 0
         AND pvs.aborted_version_cleaner_start_time IS NOT NULL
         AND pvs.aborted_version_cleaner_end_time IS NULL
         AND DATEDIFF(MINUTE, pvs.aborted_version_cleaner_start_time, SYSDATETIME()) >= 60
            THEN 1 ELSE 0
    END                                                AS flag_aborted_cleaner_running_over_60min
FROM sys.dm_tran_persistent_version_store_stats AS pvs
ORDER BY pvs.persistent_version_store_size_kb DESC;

-- ── 3. Active transactions in ADR-enabled databases ─────────────────────────
SELECT TOP (100)
    ''ADR_CLEANUP_BLOCKERS''                            AS ResultSetName,
    dt.database_id                                     AS DatabaseId,
    DB_NAME(dt.database_id)                            AS DatabaseName,
    st.session_id                                      AS SessionId,
    es.login_name                                      AS LoginName,
    es.host_name                                       AS HostName,
    es.program_name                                    AS ProgramName,
    at.transaction_id                                  AS TransactionId,
    at.transaction_begin_time                          AS TransactionBeginTime,
    DATEDIFF(SECOND, at.transaction_begin_time, SYSDATETIME())
                                                        AS TransactionAgeSeconds,
    dt.database_transaction_begin_time                 AS DatabaseTransactionBeginTime,
    dt.database_transaction_type                       AS DatabaseTransactionType,
    dt.database_transaction_state                      AS DatabaseTransactionState,
    dt.database_transaction_log_bytes_used             AS LogBytesUsed,
    er.status                                          AS RequestStatus,
    er.command                                         AS RequestCommand,
    er.wait_type                                       AS WaitType,
    er.blocking_session_id                             AS BlockingSessionId,
    ib.event_info                                      AS LastSubmittedCommand,
    CASE
        WHEN DATEDIFF(MINUTE, at.transaction_begin_time, SYSDATETIME()) >= 15
            THEN 1 ELSE 0
    END                                                AS flag_transaction_over_15min,
    CASE
        WHEN DATEDIFF(MINUTE, at.transaction_begin_time, SYSDATETIME()) >= 60
            THEN 1 ELSE 0
    END                                                AS flag_transaction_over_60min
FROM sys.dm_tran_database_transactions AS dt
JOIN sys.databases AS d
    ON d.database_id = dt.database_id
   AND d.is_accelerated_database_recovery_on = 1
JOIN sys.dm_tran_active_transactions AS at
    ON at.transaction_id = dt.transaction_id
LEFT JOIN sys.dm_tran_session_transactions AS st
    ON st.transaction_id = dt.transaction_id
LEFT JOIN sys.dm_exec_sessions AS es
    ON es.session_id = st.session_id
LEFT JOIN sys.dm_exec_requests AS er
    ON er.session_id = st.session_id
OUTER APPLY sys.dm_exec_input_buffer(st.session_id, NULL) AS ib
WHERE at.transaction_state IN (2, 5)
ORDER BY at.transaction_begin_time;';

EXEC sys.sp_executesql @Sql;
