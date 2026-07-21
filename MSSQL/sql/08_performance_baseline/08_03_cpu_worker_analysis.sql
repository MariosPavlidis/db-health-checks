-- =============================================================================
-- 08_03_cpu_worker_analysis.sql — CPU and Worker Thread Analysis
-- Chapter 8: Performance Baseline
-- Description: Analyses SQL Server CPU utilisation trends, CPU history from
--              ring buffer, NUMA node runnable task counts, and worker thread
--              exhaustion indicators.
-- Requires:    SQL Server 2016 or later (version guard below)
-- =============================================================================

IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning];
    RETURN;
END
GO

-- ── Section A: CPU utilisation by hour from query stats (last 24 hours) ───────
SELECT TOP 100
    DATEADD(HOUR, DATEDIFF(HOUR, 0, qs.last_execution_time), 0)    AS ExecutionHour,
    COUNT_BIG(*)                                                     AS QueryCount,
    SUM(qs.total_worker_time)                                        AS TotalWorkerTimeUs,
    AVG(qs.total_worker_time / NULLIF(qs.execution_count, 0))       AS AvgWorkerTimePerExecUs,
    SUM(qs.execution_count)                                          AS TotalExecutions,
    SUM(qs.total_logical_reads)                                      AS TotalLogicalReads,
    SUM(qs.total_logical_writes)                                     AS TotalLogicalWrites,
    GETDATE()                                                        AS CollectedAt
FROM sys.dm_exec_query_stats AS qs
WHERE qs.last_execution_time >= DATEADD(HOUR, -24, GETDATE())
GROUP BY DATEADD(HOUR, DATEDIFF(HOUR, 0, qs.last_execution_time), 0)
ORDER BY ExecutionHour DESC;

-- ── Section B: CPU history from ring buffer (last 4 hours) ───────────────────
DECLARE @xmlRingBuffer XML;

SELECT @xmlRingBuffer = CAST(target_data AS XML)
FROM sys.dm_xe_session_targets  AS t
JOIN sys.dm_xe_sessions          AS s ON s.address = t.event_session_address
WHERE s.name        = 'system_health'
  AND t.target_name = 'ring_buffer';

SELECT TOP 240
    DATEADD(
        ms,
        -1 * (si.cpu_ticks / CONVERT(FLOAT, si.cpu_ticks / si.ms_ticks)
              - rb.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int')),
        GETDATE()
    )                                                                           AS RecordTime,
    rb.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int')
                                                                                AS SqlCpuUtilization,
    100
      - rb.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int')
      - rb.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int')
                                                                                AS OtherCpuUtilization,
    rb.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int')
                                                                                AS SystemIdle,
    GETDATE()                                                                   AS CollectedAt
FROM @xmlRingBuffer.nodes('//RingBufferTarget/event[@name="scheduler_monitor_system_health_ring_buffer_recorded"]//Record') AS t(rb)
CROSS JOIN sys.dm_os_sys_info AS si
ORDER BY RecordTime DESC;

-- ── Section C: Runnable tasks per NUMA node ───────────────────────────────────
SELECT
    sc.parent_node_id                   AS NumaNodeId,
    COUNT(*)                            AS SchedulerCount,
    SUM(sc.runnable_tasks_count)        AS TotalRunnableTasks,
    SUM(sc.work_queue_count)            AS TotalWorkQueueCount,
    SUM(sc.active_workers_count)        AS TotalActiveWorkers,
    SUM(sc.current_tasks_count)         AS TotalCurrentTasks,
    MAX(sc.runnable_tasks_count)        AS MaxRunnableTasksOnScheduler,
    GETDATE()                           AS CollectedAt
FROM sys.dm_os_schedulers AS sc
WHERE sc.status = 'VISIBLE ONLINE'
GROUP BY sc.parent_node_id
ORDER BY sc.parent_node_id;

-- ── Section D: Worker thread exhaustion indicators ────────────────────────────
SELECT
    si.max_workers_count                AS MaxWorkersCount,
    (
        SELECT SUM(active_workers_count)
        FROM sys.dm_os_schedulers
        WHERE status = 'VISIBLE ONLINE'
    )                                   AS CurrentActiveWorkers,
    (
        SELECT SUM(work_queue_count)
        FROM sys.dm_os_schedulers
        WHERE status = 'VISIBLE ONLINE'
    )                                   AS WorkQueueDepth,
    (
        SELECT SUM(runnable_tasks_count)
        FROM sys.dm_os_schedulers
        WHERE status = 'VISIBLE ONLINE'
    )                                   AS TotalRunnableTasks,
    CAST(
        (
            SELECT SUM(active_workers_count) * 100.0
            FROM sys.dm_os_schedulers
            WHERE status = 'VISIBLE ONLINE'
        ) / NULLIF(si.max_workers_count, 0)
    AS DECIMAL(5,1))                    AS WorkerUtilizationPct,
    -- THREADPOOL waits indicate exhaustion
    ws.waiting_tasks_count              AS ThreadpoolWaitingTasks,
    ws.wait_time_ms                     AS ThreadpoolWaitTimeMs,
    GETDATE()                           AS CollectedAt
FROM sys.dm_os_sys_info AS si
LEFT JOIN sys.dm_os_wait_stats AS ws
    ON ws.wait_type = 'THREADPOOL';
