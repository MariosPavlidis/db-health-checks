-- =============================================================================
-- 10_02_lock_escalation.sql — Lock Escalation and Current Lock Snapshot
-- Chapter 10: Blocking, Locking, and Deadlocks
-- Description: Reports historical LCK_* wait stats, a current snapshot of
--              active locks from sys.dm_tran_locks grouped by type and mode,
--              table-level (OBJECT) lock escalations, and the lock escalation
--              performance counter.
-- Requires:    SQL Server 2016 or later (version guard below)
-- =============================================================================

IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning];
    RETURN;
END
GO

-- ── Section A: LCK_* wait statistics (cumulative since restart) ───────────────
SELECT
    ws.wait_type                                            AS WaitType,
    ws.waiting_tasks_count                                  AS WaitingTasksCount,
    ws.wait_time_ms                                         AS WaitTimeMs,
    CASE WHEN ws.waiting_tasks_count > 0
         THEN CAST(ws.wait_time_ms * 1.0
                   / ws.waiting_tasks_count AS DECIMAL(18,2))
         ELSE 0 END                                         AS AvgWaitMs,
    ws.max_wait_time_ms                                     AS MaxWaitTimeMs,
    ws.signal_wait_time_ms                                  AS SignalWaitTimeMs,
    ws.wait_time_ms - ws.signal_wait_time_ms                AS ResourceWaitTimeMs,
    CAST(ws.wait_time_ms * 100.0
         / NULLIF(SUM(ws.wait_time_ms) OVER (), 0)
         AS DECIMAL(10,2))                                  AS PctOfAllLockWaits,
    GETDATE()                                               AS CollectedAt
FROM sys.dm_os_wait_stats AS ws
WHERE ws.wait_type LIKE 'LCK_%'
  AND ws.wait_time_ms > 0
ORDER BY ws.wait_time_ms DESC;

-- ── Section B: Current lock snapshot grouped by type and mode ─────────────────
SELECT
    tl.resource_type,
    tl.request_mode,
    DB_NAME(tl.resource_database_id)                        AS DatabaseName,
    tl.resource_database_id,
    COUNT(*)                                                AS LockCount,
    SUM(CASE WHEN tl.request_status = 'GRANT'  THEN 1 ELSE 0 END) AS GrantedCount,
    SUM(CASE WHEN tl.request_status = 'WAIT'   THEN 1 ELSE 0 END) AS WaitingCount,
    SUM(CASE WHEN tl.request_status = 'CONVERT' THEN 1 ELSE 0 END) AS ConvertCount,
    MAX(CASE WHEN tl.resource_type = 'OBJECT' THEN 1 ELSE 0 END)   AS HasTableLevelLock,
    GETDATE()                                               AS CollectedAt
FROM sys.dm_tran_locks AS tl
WHERE tl.request_session_id > 50   -- exclude system sessions
GROUP BY
    tl.resource_type,
    tl.request_mode,
    tl.resource_database_id
ORDER BY LockCount DESC;

-- ── Section C: Table-level (OBJECT) lock detail ────────────────────────────────
SELECT
    tl.request_session_id                                   AS SessionId,
    DB_NAME(tl.resource_database_id)                        AS DatabaseName,
    OBJECT_NAME(tl.resource_associated_entity_id,
                tl.resource_database_id)                    AS ObjectName,
    tl.resource_associated_entity_id                        AS ObjectId,
    tl.request_mode                                         AS LockMode,
    tl.request_status                                       AS LockStatus,
    tl.request_type                                         AS LockType,
    s.login_name,
    s.host_name,
    s.program_name,
    s.open_transaction_count,
    GETDATE()                                               AS CollectedAt
FROM sys.dm_tran_locks AS tl
JOIN sys.dm_exec_sessions AS s
    ON s.session_id = tl.request_session_id
WHERE tl.resource_type = 'OBJECT'
  AND tl.request_session_id > 50
ORDER BY tl.resource_database_id, tl.request_mode;

-- ── Section D: Lock escalation performance counter ────────────────────────────
SELECT
    RTRIM(pc.object_name)                                   AS CounterObject,
    RTRIM(pc.counter_name)                                  AS CounterName,
    RTRIM(pc.instance_name)                                 AS InstanceName,
    pc.cntr_value                                           AS CounterValue,
    GETDATE()                                               AS CollectedAt
FROM sys.dm_os_performance_counters AS pc
WHERE pc.counter_name IN ('Lock Escalations/sec', 'Table Lock Escalations/sec')
ORDER BY pc.object_name, pc.counter_name;
