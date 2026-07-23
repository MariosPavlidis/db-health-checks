-- =============================================================================
-- Utility:      00 — Operational Tools
-- Section:      00.01 — Session Monitor and Kill
-- Description:  Monitor active health check sessions in real time and kill
--               them if they are loading the server. Run this in a separate
--               SSMS/ADS window on the same instance while health check
--               scripts are executing.
--
-- PRODUCTION SAFETY NOTE:
--   11_01_fragmentation.sql uses sys.dm_db_index_physical_stats (LIMITED mode)
--   inside a cursor loop across every user database. Even in LIMITED mode this
--   reads allocation pages for all indexes in every database and can run for
--   several minutes on large instances, generating sustained I/O reads.
--
--   11_03_unused_indexes.sql reads sys.dm_db_index_usage_stats (in-memory,
--   no I/O) but includes a size subquery over sys.partitions /
--   sys.allocation_units that causes catalog scans on databases with many
--   indexes.
--
-- WHEN TO KILL:
--   ElapsedSec > 120 and PhysicalReads climbing fast  → consider killing
--   WaitType = PAGEIOLATCH_SH sustained                → kill immediately
--   BlockedBy > 0                                      → kill the HC session
--   ElapsedSec > 30 and WaitType = ASYNC_NETWORK_IO   → results returning, safe
-- =============================================================================

SET NOCOUNT ON;

-- ============================================================
-- 1. Active health check session monitor
--    Refresh this query every 10–30 seconds.
-- ============================================================

SELECT
    r.session_id                                            AS SessionID,
    s.login_name                                            AS LoginName,
    s.host_name                                             AS HostName,
    s.program_name                                          AS ProgramName,
    DB_NAME(r.database_id)                                  AS CurrentDatabase,
    r.status                                                AS Status,
    r.command                                               AS Command,
    r.wait_type                                             AS WaitType,
    r.wait_time          / 1000                             AS WaitSec,
    r.total_elapsed_time / 1000                             AS ElapsedSec,
    r.cpu_time           / 1000                             AS CpuSec,
    r.logical_reads                                         AS LogicalReads,
    r.reads                                                 AS PhysicalReads,
    r.blocking_session_id                                   AS BlockedBy,
    r.open_transaction_count                                AS OpenTxns,
    SUBSTRING(
        t.text,
        (r.statement_start_offset / 2) + 1,
        CASE r.statement_end_offset
            WHEN -1 THEN DATALENGTH(t.text)
            ELSE r.statement_end_offset
        END / 2 - (r.statement_start_offset / 2) + 1
    )                                                       AS CurrentStatement,
    t.text                                                  AS FullBatchText,

    -- Copy and run this value to kill the session immediately
    'KILL ' + CAST(r.session_id AS VARCHAR(10)) + ';'      AS KillCommand

FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions  s  ON  s.session_id = r.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t

WHERE s.is_user_process = 1
  AND s.session_id <> @@SPID   -- exclude this monitoring session

  -- Matches sessions running fragmentation or index usage health check scripts.
  -- Add filters for login_name or program_name if needed to narrow scope.
  AND (
        t.text LIKE '%dm_db_index_physical_stats%'   -- 11_01_fragmentation
     OR t.text LIKE '%dm_db_index_usage_stats%'      -- 11_03_unused_indexes
     OR t.text LIKE '%db_cursor%'                    -- any HC cursor loop
  )

ORDER BY r.total_elapsed_time DESC;


-- ============================================================
-- 2. Catch-all: all active sessions running > 30 seconds
--    Use this if you need to identify the SPID without knowing
--    which filter to apply above.
-- ============================================================
/*
SELECT
    r.session_id,
    s.login_name,
    DB_NAME(r.database_id)          AS CurrentDatabase,
    r.status,
    r.wait_type,
    r.total_elapsed_time / 1000     AS ElapsedSec,
    r.logical_reads,
    r.reads                         AS PhysicalReads,
    r.blocking_session_id           AS BlockedBy,
    'KILL ' + CAST(r.session_id AS VARCHAR(10)) + ';'   AS KillCommand,
    SUBSTRING(t.text, 1, 200)       AS StatementPreview
FROM sys.dm_exec_requests  r
JOIN sys.dm_exec_sessions  s  ON  s.session_id = r.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE s.is_user_process = 1
  AND s.session_id <> @@SPID
  AND r.total_elapsed_time > 30000    -- 30 seconds
ORDER BY r.total_elapsed_time DESC;
*/


-- ============================================================
-- 3. KILL — paste the KillCommand value from the query above,
--    or substitute the SPID directly:
-- ============================================================
-- KILL <session_id>;
