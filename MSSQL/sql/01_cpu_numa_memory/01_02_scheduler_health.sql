-- =============================================================================
-- Chapter:      01 — CPU, NUMA, and Memory
-- Section:      01.02 — Scheduler Health
-- Checklist:    1.2
-- Min Version:  SQL Server 2016 (v13)
-- Description:  Per-scheduler runnable task queue depth, worker thread usage,
--               pending disk I/O, and load factor. A runnable_tasks_count > 2
--               on any visible scheduler indicates CPU pressure. Results are
--               ordered highest pressure first.
-- =============================================================================

IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning];
    RETURN;
END
GO

SET NOCOUNT ON;

SELECT
    s.scheduler_id                          AS SchedulerId,
    s.parent_node_id                        AS NumaNodeId,
    s.cpu_id                                AS CpuId,
    s.status                                AS Status,
    s.is_online                             AS IsOnline,
    s.current_workers_count                 AS CurrentWorkers,
    s.active_workers_count                  AS ActiveWorkers,
    s.runnable_tasks_count                  AS RunnableTasks,
    s.work_queue_count                      AS WorkQueueDepth,
    s.pending_disk_io_count                 AS PendingDiskIo,
    s.load_factor                           AS LoadFactor,
    s.yield_count                           AS YieldCount,
    CASE
        WHEN s.runnable_tasks_count > 2 THEN 1
        ELSE 0
    END                                     AS flag_cpu_pressure
FROM sys.dm_os_schedulers s
WHERE s.status IN ('VISIBLE ONLINE', 'VISIBLE OFFLINE')
  AND s.scheduler_id < 255                 -- exclude hidden/system schedulers
ORDER BY s.runnable_tasks_count DESC,
         s.scheduler_id;
