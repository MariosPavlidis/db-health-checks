-- =============================================================================
-- Chapter:      01 — CPU, NUMA, and Memory
-- Section:      01.03 — Parallelism Configuration
-- Checklist:    1.3
-- Min Version:  SQL Server 2016 (v13)
-- Description:  Four views of parallelism configuration and behaviour:
--                 1. Instance-level MAXDOP and Cost Threshold for Parallelism,
--                    validated against NUMA topology.
--                 2. Database-scoped MAXDOP overrides for all online databases
--                    (SQL Server 2016+).
--                 3. Parallelism-related wait statistics since last restart:
--                    CXPACKET, CXCONSUMER, EXCHANGE, SOS_SCHEDULER_YIELD.
--                 4. Currently active parallel requests snapshot — DOP per
--                    session, CPU and elapsed time.
--
--               Flags:
--                 flag_maxdop_zero_many_cpus  — MAXDOP=0 on >8 logical CPUs
--                 flag_ctp_default            — Cost Threshold still at 5
--                 flag_maxdop_not_validated   — instance MAXDOP = 0 or > half
--                                               the logical CPUs per NUMA node
--                 flag_db_maxdop_override     — database has a non-zero MAXDOP
--                                               that differs from the instance
--                 flag_excessive_cxpacket     — CXPACKET > 10% of total waits
--                 flag_active_high_dop        — currently running query DOP
--                                               equals the instance CPU count
-- =============================================================================

IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning];
    RETURN;
END
GO

SET NOCOUNT ON;

-- ── 1. Instance-level MAXDOP and Cost Threshold ───────────────────────────────
SELECT
    si.cpu_count                                AS LogicalCpuCount,
    si.socket_count                             AS SocketCount,
    si.cores_per_socket                         AS CoresPerSocket,
    si.numa_node_count                          AS NumaNodeCount,
    si.cpu_count / NULLIF(si.numa_node_count,0) AS LogicalCpusPerNode,
    maxdop.value_in_use                         AS MaxDopEffective,
    maxdop.value                                AS MaxDopConfigured,
    ctp.value_in_use                            AS CostThresholdEffective,
    ctp.value                                   AS CostThresholdConfigured,
    CASE
        WHEN maxdop.value_in_use = 0
         AND si.cpu_count > 8                   THEN 1 ELSE 0
    END                                         AS flag_maxdop_zero_many_cpus,
    CASE
        WHEN ctp.value_in_use = 5               THEN 1 ELSE 0
    END                                         AS flag_ctp_default,
    -- Flag: MAXDOP exceeds the recommended per-NUMA ceiling
    CASE
        WHEN si.numa_node_count > 1
         AND maxdop.value_in_use > si.cpu_count / si.numa_node_count
                                                THEN 1 ELSE 0
    END                                         AS flag_maxdop_exceeds_numa_ceiling
FROM sys.configurations maxdop
CROSS JOIN sys.configurations ctp
CROSS JOIN sys.dm_os_sys_info si
WHERE maxdop.name = 'max degree of parallelism'
  AND ctp.name   = 'cost threshold for parallelism';

-- ── 2. Database-scoped MAXDOP overrides ──────────────────────────────────────
SELECT
    d.name                                      AS DatabaseName,
    d.database_id                               AS DatabaseId,
    dsc.value                                   AS DbScopedMaxDop,
    instance_maxdop.value_in_use                AS InstanceMaxDop,
    CASE
        WHEN TRY_CAST(dsc.value AS INT) <> 0
         AND TRY_CAST(dsc.value AS INT) <> instance_maxdop.value_in_use
                                                THEN 1 ELSE 0
    END                                         AS flag_db_maxdop_override
FROM sys.databases d
CROSS JOIN sys.configurations instance_maxdop
OUTER APPLY (
    SELECT sc.value
    FROM sys.database_scoped_configurations sc
    WHERE sc.name = 'MAXDOP'
      AND sc.database_id = d.database_id
) dsc
WHERE d.state_desc  = 'ONLINE'
  AND d.database_id > 4
  AND instance_maxdop.name = 'max degree of parallelism'
ORDER BY d.name;

-- ── 3. Parallelism-related wait statistics ────────────────────────────────────
DECLARE @TotalWaitMs BIGINT;
SELECT @TotalWaitMs = SUM(wait_time_ms)
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN (
    'SLEEP_TASK','BROKER_TO_FLUSH','BROKER_TASK_STOP','CLR_AUTO_EVENT',
    'DISPATCHER_QUEUE_SEMAPHORE','FT_IFTS_SCHEDULER_IDLE_WAIT',
    'HADR_FILESTREAM_IOMGR_IOCOMPLETION','HADR_WORK_QUEUE',
    'LAZYWRITER_SLEEP','LOGMGR_QUEUE','ONDEMAND_TASK_QUEUE',
    'REQUEST_FOR_DEADLOCK_SEARCH','RESOURCE_QUEUE','SERVER_IDLE_CHECK',
    'SLEEP_DBSTARTUP','SLEEP_DCOMSTARTUP','SLEEP_MASTERDBREADY',
    'SLEEP_MASTERMDREADY','SLEEP_MASTERUPGRADED','SLEEP_MSDBSTARTUP',
    'SLEEP_SYSTEMTASK','SLEEP_TEMPDBSTARTUP','SNI_HTTP_ACCEPT',
    'SP_SERVER_DIAGNOSTICS_SLEEP','SQLTRACE_BUFFER_FLUSH',
    'SQLTRACE_INCREMENTAL_FLUSH_SLEEP','WAIT_XTP_OFFLINE_CKPT_NEW_LOG',
    'WAITFOR','XE_DISPATCHER_WAIT','XE_TIMER_EVENT',
    'BROKER_EVENTHANDLER','CHECKPOINT_QUEUE','DBMIRROR_EVENTS_QUEUE',
    'SQLTRACE_WAIT_ENTRIES','WAIT_XTP_CKPT_CLOSE'
);

SELECT
    w.wait_type                                 AS WaitType,
    w.waiting_tasks_count                       AS WaitingTasksCount,
    w.wait_time_ms                              AS TotalWaitMs,
    w.max_wait_time_ms                          AS MaxWaitMs,
    CAST(w.wait_time_ms * 100.0
         / NULLIF(@TotalWaitMs, 0) AS DECIMAL(5,2))  AS PctOfTotalWaits,
    CASE
        WHEN w.wait_type = 'CXPACKET'
         AND w.wait_time_ms * 100.0
             / NULLIF(@TotalWaitMs, 0) > 10    THEN 1 ELSE 0
    END                                         AS flag_excessive_cxpacket
FROM sys.dm_os_wait_stats w
WHERE w.wait_type IN (
    'CXPACKET',
    'CXCONSUMER',
    'EXCHANGE',
    'SOS_SCHEDULER_YIELD'
)
ORDER BY w.wait_time_ms DESC;

-- ── 4. Currently active parallel requests ────────────────────────────────────
SELECT
    r.session_id                                AS SessionId,
    r.dop                                       AS DegreeOfParallelism,
    r.status                                    AS Status,
    r.wait_type                                 AS WaitType,
    r.cpu_time / 1000                           AS CpuSec,
    r.total_elapsed_time / 1000                 AS ElapsedSec,
    r.logical_reads                             AS LogicalReads,
    DB_NAME(r.database_id)                      AS DatabaseName,
    si.cpu_count                                AS InstanceCpuCount,
    CASE
        WHEN r.dop >= si.cpu_count              THEN 1 ELSE 0
    END                                         AS flag_active_high_dop
FROM sys.dm_exec_requests r
CROSS JOIN sys.dm_os_sys_info si
WHERE r.dop > 1
  AND r.session_id <> @@SPID
ORDER BY r.dop DESC, r.cpu_time DESC;
