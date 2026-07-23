-- =============================================================================
-- Utility:      00 — Operational Tools
-- Section:      00.01 — Session Monitor and Kill
-- Description:  Monitor active sessions in real time. Run in a separate SSMS
--               window and refresh every 10–30 seconds. Copy the KillCommand
--               value to stop any session immediately.
-- =============================================================================

SELECT
    r.session_id,
    s.login_name,
    DB_NAME(r.database_id)                                  AS CurrentDatabase,
    r.status,
    r.wait_type,
    r.total_elapsed_time / 1000                             AS ElapsedSec,
    r.percent_complete                                      AS PercentComplete,
    DATEADD(ms, r.estimated_completion_time, GETDATE())     AS EstimatedCompletionTime,
    r.logical_reads,
    r.reads                                                 AS PhysicalReads,
    r.blocking_session_id                                   AS BlockedBy,
    'KILL ' + CAST(r.session_id AS VARCHAR(10)) + ';'       AS KillCommand,
    SUBSTRING(t.text, 1, 200)                               AS StatementPreview
FROM sys.dm_exec_requests  r
JOIN sys.dm_exec_sessions  s  ON  s.session_id = r.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE s.is_user_process = 1
  AND s.session_id <> @@SPID
  AND r.wait_type <> 'SP_SERVER_DIAGNOSTICS_SLEEP'
ORDER BY r.total_elapsed_time DESC;
