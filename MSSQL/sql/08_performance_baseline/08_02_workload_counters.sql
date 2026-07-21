-- =============================================================================
-- 08_02_workload_counters.sql — Workload Performance Counters
-- Chapter 8: Performance Baseline
-- Description: Collects key SQL Server performance counters from
--              sys.dm_os_performance_counters and CPU utilisation history
--              from sys.dm_os_ring_buffers (last 1 hour).
-- Requires:    SQL Server 2016 or later (version guard below)
-- =============================================================================

IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning];
    RETURN;
END
GO

-- ── Section A: Key performance counters ──────────────────────────────────────
SELECT
    RTRIM(pc.object_name)   AS CounterObject,
    RTRIM(pc.counter_name)  AS CounterName,
    RTRIM(pc.instance_name) AS InstanceName,
    pc.cntr_value           AS CounterValue,
    GETDATE()               AS CollectedAt
FROM sys.dm_os_performance_counters AS pc
WHERE
    -- SQL Statistics
    (pc.object_name LIKE '%SQL Statistics%'
        AND pc.counter_name IN (
            'Batch Requests/sec',
            'SQL Compilations/sec',
            'SQL Re-Compilations/sec'
        )
    )
    OR
    -- Buffer Manager
    (pc.object_name LIKE '%Buffer Manager%'
        AND pc.counter_name IN (
            'Page reads/sec',
            'Page writes/sec',
            'Lazy writes/sec',
            'Checkpoint pages/sec',
            'Buffer cache hit ratio',
            'Buffer cache hit ratio base',
            'Page life expectancy',
            'Free list stalls/sec',
            'Disk read IO/sec',
            'Disk write IO/sec'
        )
    )
    OR
    -- Memory Manager
    (pc.object_name LIKE '%Memory Manager%'
        AND pc.counter_name IN (
            'Memory Grants Pending',
            'Target Server Memory (KB)',
            'Total Server Memory (KB)'
        )
    )
    OR
    -- General Statistics
    (pc.object_name LIKE '%General Statistics%'
        AND pc.counter_name IN (
            'User Connections',
            'Logins/sec',
            'Logouts/sec'
        )
    )
    OR
    -- Locks
    (pc.object_name LIKE '%Locks%'
        AND pc.counter_name IN (
            'Number of Deadlocks/sec',
            'Lock Escalations/sec'
        )
        AND pc.instance_name = '_Total'
    )
    OR
    -- Access Methods
    (pc.object_name LIKE '%Access Methods%'
        AND pc.counter_name IN (
            'Worktables Created/sec',
            'Table Lock Escalations/sec',
            'Full Scans/sec',
            'Index Searches/sec'
        )
    )
    OR
    -- Databases (aggregate _Total)
    (pc.object_name LIKE '%Databases%'
        AND pc.counter_name IN (
            'Log Flushes/sec',
            'Log Bytes Flushed/sec',
            'Transactions/sec'
        )
        AND pc.instance_name = '_Total'
    )
ORDER BY pc.object_name, pc.counter_name, pc.instance_name;

-- ── Section B: Current blocked process count ──────────────────────────────────
SELECT
    'Blocked process count'             AS CounterName,
    COUNT(*)                            AS CounterValue,
    GETDATE()                           AS CollectedAt
FROM sys.dm_exec_requests
WHERE blocking_session_id > 0;

-- ── Section C: CPU utilisation history (last 60 minutes) ─────────────────────
-- Reads from the system_health ring buffer scheduler monitor records.
DECLARE @xmlRingBuffer XML;

SELECT @xmlRingBuffer = CAST(target_data AS XML)
FROM sys.dm_xe_session_targets  AS t
JOIN sys.dm_xe_sessions          AS s ON s.address = t.event_session_address
WHERE s.name        = 'system_health'
  AND t.target_name = 'ring_buffer';

SELECT TOP 60
    DATEADD(ms, -1 * (si.cpu_ticks / CONVERT(FLOAT, si.cpu_ticks / si.ms_ticks)
                      - rb.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int')),
            GETDATE())                                                          AS ApproxRecordTime,
    rb.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int')
                                                                               AS SqlCpuUtilization,
    rb.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int')
                                                                               AS SystemIdle,
    100
      - rb.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int')
      - rb.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int')
                                                                               AS OtherProcessCpu,
    GETDATE()                                                                  AS CollectedAt
FROM @xmlRingBuffer.nodes('//RingBufferTarget/event[@name="scheduler_monitor_system_health_ring_buffer_recorded"]//Record') AS t(rb)
CROSS JOIN sys.dm_os_sys_info AS si
ORDER BY ApproxRecordTime DESC;
