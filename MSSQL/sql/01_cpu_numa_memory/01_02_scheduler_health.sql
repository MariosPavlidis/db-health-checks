-- =============================================================================
-- Chapter:      01 — CPU, NUMA, and Memory
-- Section:      01.02 — Scheduler Health
-- Checklist:    1.2
-- Min Version:  SQL Server 2016 (v13)
-- Description:  Four views of scheduler health:
--                 1. Per-scheduler runnable task queue, worker usage, pending
--                    I/O, and load factor — ordered by pressure descending.
--                 2. Per-NUMA node scheduler summary — detects imbalance across
--                    nodes.
--                 3. Instance-level worker thread saturation — compares active
--                    workers against max_workers_count.
--                 4. THREADPOOL wait stats — non-zero waiting_tasks_count
--                    confirms worker thread exhaustion.
--
--               Flags:
--                 flag_cpu_pressure      — runnable_tasks_count > 2
--                 flag_imbalance         — runnable tasks > 2x instance average
--                 flag_thread_exhaustion — instance active workers > 90% of max
--                 flag_threadpool_waits  — THREADPOOL waiting_tasks_count > 0
-- =============================================================================

IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning];
    RETURN;
END
GO

SET NOCOUNT ON;

-- ── 1. Per-scheduler detail ───────────────────────────────────────────────────
SELECT
    s.scheduler_id                              AS SchedulerId,
    s.parent_node_id                            AS NumaNodeId,
    s.cpu_id                                    AS CpuId,
    s.status                                    AS Status,
    s.is_online                                 AS IsOnline,
    s.current_workers_count                     AS CurrentWorkers,
    s.active_workers_count                      AS ActiveWorkers,
    s.runnable_tasks_count                      AS RunnableTasks,
    s.work_queue_count                          AS WorkQueueDepth,
    s.pending_disk_io_count                     AS PendingDiskIo,
    s.load_factor                               AS LoadFactor,
    s.yield_count                               AS YieldCount,
    -- CPU pressure: runnable queue > 2 on any visible scheduler
    CASE WHEN s.runnable_tasks_count > 2        THEN 1 ELSE 0 END AS flag_cpu_pressure,
    -- Imbalance: this scheduler's runnable tasks > 2x the instance average
    CASE
        WHEN avg_runnable.AvgRunnable > 0
         AND s.runnable_tasks_count > avg_runnable.AvgRunnable * 2
                                                THEN 1 ELSE 0
    END                                         AS flag_imbalance
FROM sys.dm_os_schedulers s
CROSS JOIN (
    SELECT AVG(CAST(runnable_tasks_count AS FLOAT)) AS AvgRunnable
    FROM sys.dm_os_schedulers
    WHERE status = 'VISIBLE ONLINE'
      AND scheduler_id < 255
) avg_runnable
WHERE s.status IN ('VISIBLE ONLINE', 'VISIBLE OFFLINE')
  AND s.scheduler_id < 255
ORDER BY s.runnable_tasks_count DESC,
         s.scheduler_id;

-- ── 2. Per-NUMA node scheduler summary ───────────────────────────────────────
SELECT
    s.parent_node_id                            AS NumaNodeId,
    COUNT(*)                                    AS SchedulerCount,
    SUM(s.current_workers_count)                AS CurrentWorkers,
    SUM(s.active_workers_count)                 AS ActiveWorkers,
    SUM(s.runnable_tasks_count)                 AS TotalRunnableTasks,
    MAX(s.runnable_tasks_count)                 AS MaxRunnableTasks,
    SUM(s.work_queue_count)                     AS TotalWorkQueue,
    SUM(s.pending_disk_io_count)                AS TotalPendingDiskIo,
    -- Flag: any scheduler on this NUMA node is under pressure
    MAX(CASE WHEN s.runnable_tasks_count > 2 THEN 1 ELSE 0 END) AS flag_node_cpu_pressure
FROM sys.dm_os_schedulers s
WHERE s.status IN ('VISIBLE ONLINE', 'VISIBLE OFFLINE')
  AND s.scheduler_id < 255
GROUP BY s.parent_node_id
ORDER BY s.parent_node_id;

-- ── 3. Instance-level worker thread saturation ────────────────────────────────
SELECT
    si.max_workers_count                        AS MaxWorkers,
    SUM(s.current_workers_count)                AS TotalCurrentWorkers,
    SUM(s.active_workers_count)                 AS TotalActiveWorkers,
    CAST(SUM(s.active_workers_count) AS FLOAT)
        / NULLIF(si.max_workers_count, 0) * 100 AS ActiveWorkerPct,
    -- Flag: active workers consuming > 90% of the thread pool
    CASE
        WHEN SUM(s.active_workers_count) >
             si.max_workers_count * 0.9         THEN 1 ELSE 0
    END                                         AS flag_thread_exhaustion
FROM sys.dm_os_schedulers s
CROSS JOIN sys.dm_os_sys_info si
WHERE s.status IN ('VISIBLE ONLINE', 'VISIBLE OFFLINE')
  AND s.scheduler_id < 255
GROUP BY si.max_workers_count;

-- ── 4. THREADPOOL wait stats ──────────────────────────────────────────────────
SELECT
    w.wait_type                                 AS WaitType,
    w.waiting_tasks_count                       AS WaitingTasksCount,
    w.wait_time_ms                              AS TotalWaitMs,
    w.max_wait_time_ms                          AS MaxWaitMs,
    -- Flag: any THREADPOOL waits recorded since last restart
    CASE WHEN w.waiting_tasks_count > 0         THEN 1 ELSE 0 END AS flag_threadpool_waits
FROM sys.dm_os_wait_stats w
WHERE w.wait_type = 'THREADPOOL';
