-- =============================================================================
-- 10_01_blocking_analysis.sql — Current Blocking Chain Analysis
-- Chapter 10: Blocking, Locking, and Deadlocks
-- Description: Identifies active blocking chains from sys.dm_exec_requests,
--              active transactions blocking others, and sleeping sessions with
--              open transactions that may be causing contention.
-- Requires:    SQL Server 2016 or later (version guard below)
-- =============================================================================

IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning];
    RETURN;
END
GO

-- ── Section A: Active blocking chains ─────────────────────────────────────────
SELECT
    r.blocking_session_id                                           AS HeadBlockerSessionId,
    r.session_id                                                    AS BlockedSessionId,
    r.wait_type,
    r.wait_time / 1000.0                                           AS WaitTimeSec,
    r.wait_resource                                                 AS LockedResource,
    r.status                                                        AS RequestStatus,
    r.command                                                       AS CommandType,
    r.cpu_time                                                      AS CpuTimeMs,
    r.total_elapsed_time                                            AS TotalElapsedMs,
    r.reads                                                         AS LogicalReads,
    s.login_name,
    s.host_name,
    s.program_name,
    s.login_time,
    s.last_request_start_time,
    s.open_transaction_count                                        AS OpenTransactionCount,
    t.transaction_begin_time                                        AS TxnBeginTime,
    DATEDIFF(SECOND, t.transaction_begin_time, GETDATE())          AS TxnAgeSec,
    CASE t.transaction_type
        WHEN 1 THEN 'Read/Write'
        WHEN 2 THEN 'Read-Only'
        WHEN 3 THEN 'System'
        WHEN 4 THEN 'Distributed'
        ELSE CAST(t.transaction_type AS NVARCHAR(10))
    END                                                             AS TransactionType,
    CASE t.transaction_state
        WHEN 0 THEN 'Uninitialized'
        WHEN 1 THEN 'Not Started'
        WHEN 2 THEN 'Active'
        WHEN 3 THEN 'Ended'
        WHEN 4 THEN 'Commit Initiated'
        WHEN 5 THEN 'Prepared'
        WHEN 6 THEN 'Committed'
        WHEN 7 THEN 'Rolling Back'
        WHEN 8 THEN 'Rolled Back'
        ELSE CAST(t.transaction_state AS NVARCHAR(10))
    END                                                             AS TransactionState,
    SUBSTRING(
        st.text,
        (r.statement_start_offset / 2) + 1,
        (
            CASE r.statement_end_offset
                WHEN -1 THEN DATALENGTH(st.text)
                ELSE r.statement_end_offset
            END - r.statement_start_offset
        ) / 2 + 1
    )                                                               AS CurrentStatement,
    st.text                                                         AS FullBatchText,
    s_blocker.login_name                                            AS BlockerLoginName,
    s_blocker.host_name                                             AS BlockerHostName,
    s_blocker.program_name                                          AS BlockerProgramName,
    s_blocker.status                                                AS BlockerStatus,
    s_blocker.open_transaction_count                                AS BlockerOpenTransactionCount,
    GETDATE()                                                       AS CollectedAt
FROM sys.dm_exec_requests AS r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS st
JOIN sys.dm_exec_sessions AS s
    ON s.session_id = r.session_id
LEFT JOIN sys.dm_tran_session_transactions AS tst
    ON tst.session_id = r.session_id
LEFT JOIN sys.dm_tran_active_transactions AS t
    ON t.transaction_id = tst.transaction_id
LEFT JOIN sys.dm_exec_sessions AS s_blocker
    ON s_blocker.session_id = r.blocking_session_id
WHERE r.blocking_session_id > 0
ORDER BY r.wait_time DESC;

-- ── Section B: Blocking chain depth summary ────────────────────────────────────
-- Count distinct head blockers and total blocked sessions
SELECT
    COUNT(DISTINCT r.blocking_session_id)   AS UniqueHeadBlockerCount,
    COUNT(*)                                AS TotalBlockedSessionCount,
    MAX(r.wait_time) / 1000.0              AS MaxWaitTimeSec,
    AVG(r.wait_time) / 1000.0             AS AvgWaitTimeSec,
    GETDATE()                               AS CollectedAt
FROM sys.dm_exec_requests AS r
WHERE r.blocking_session_id > 0;

-- ── Section C: Sleeping sessions with open transactions ────────────────────────
SELECT
    s.session_id,
    s.status,
    s.login_name,
    s.host_name,
    s.program_name,
    s.open_transaction_count,
    s.last_request_start_time,
    s.last_request_end_time,
    DATEDIFF(SECOND, s.last_request_end_time, GETDATE())           AS IdleSinceLastRequestSec,
    t.transaction_begin_time,
    DATEDIFF(SECOND, t.transaction_begin_time, GETDATE())          AS TxnAgeSec,
    CASE t.transaction_type
        WHEN 1 THEN 'Read/Write'
        WHEN 2 THEN 'Read-Only'
        WHEN 3 THEN 'System'
        WHEN 4 THEN 'Distributed'
        ELSE CAST(t.transaction_type AS NVARCHAR(10))
    END                                                             AS TransactionType,
    CASE t.transaction_state
        WHEN 0 THEN 'Uninitialized'
        WHEN 1 THEN 'Not Started'
        WHEN 2 THEN 'Active'
        WHEN 3 THEN 'Ended'
        WHEN 4 THEN 'Commit Initiated'
        WHEN 5 THEN 'Prepared'
        WHEN 6 THEN 'Committed'
        WHEN 7 THEN 'Rolling Back'
        WHEN 8 THEN 'Rolled Back'
        ELSE CAST(t.transaction_state AS NVARCHAR(10))
    END                                                             AS TransactionState,
    CASE t.dtc_state
        WHEN 1 THEN 'Active'
        WHEN 2 THEN 'Prepared'
        WHEN 3 THEN 'Committed'
        WHEN 4 THEN 'Aborted'
        WHEN 5 THEN 'Recovered'
        ELSE CAST(t.dtc_state AS NVARCHAR(10))
    END                                                             AS DtcState,
    GETDATE()                                                       AS CollectedAt
FROM sys.dm_exec_sessions AS s
JOIN sys.dm_tran_session_transactions AS tst
    ON tst.session_id = s.session_id
JOIN sys.dm_tran_active_transactions AS t
    ON t.transaction_id = tst.transaction_id
WHERE s.status = 'sleeping'
  AND s.session_id > 50                  -- exclude system sessions
ORDER BY t.transaction_begin_time;
