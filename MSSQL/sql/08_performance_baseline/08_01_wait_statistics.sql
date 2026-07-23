-- =============================================================================
-- 08_01_wait_statistics.sql — Wait Statistics Analysis
-- Chapter 8: Performance Baseline
-- Description: Collects wait statistics from sys.dm_os_wait_stats, excludes
--              benign waits, calculates percentages and signal vs resource
--              waits, and categorises each wait type.
-- Requires:    SQL Server 2016 or later (version guard below)
-- =============================================================================

IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning];
    RETURN;
END
GO

-- ── Instance cumulative wait summary (all waits since last restart) ───────────
SELECT
    'INSTANCE_TOTAL'                                                            AS WaitType,
    SUM(ws.waiting_tasks_count)                                                 AS WaitingTasksCount,
    SUM(ws.wait_time_ms)                                                        AS WaitTimeMs,
    CASE WHEN SUM(ws.waiting_tasks_count) > 0
         THEN CAST(SUM(ws.wait_time_ms) * 1.0
                   / SUM(ws.waiting_tasks_count) AS DECIMAL(18,2))
         ELSE 0 END                                                             AS AvgWaitMs,
    SUM(ws.signal_wait_time_ms)                                                 AS SignalWaitTimeMs,
    SUM(ws.wait_time_ms - ws.signal_wait_time_ms)                              AS ResourceWaitTimeMs,
    MAX(ws.max_wait_time_ms)                                                    AS MaxWaitTimeMs,
    CAST(100.00 AS DECIMAL(10,2))                                               AS WaitPct,
    'SUMMARY'                                                                   AS WaitCategory,
    DATEDIFF(MINUTE, si.sqlserver_start_time, GETDATE())                       AS UptimeMinutes,
    si.sqlserver_start_time                                                     AS SqlServerStartTime,
    GETDATE()                                                                   AS CollectedAt
FROM sys.dm_os_wait_stats AS ws
CROSS JOIN (SELECT sqlserver_start_time FROM sys.dm_os_sys_info) AS si
WHERE ws.wait_time_ms > 0;

-- ── Per-wait-type breakdown (benign waits excluded) ───────────────────────────
WITH BenignWaits AS (
    SELECT wait_type FROM (VALUES
        ('SLEEP_TASK'),
        ('LAZYWRITER_SLEEP'),
        ('SQLTRACE_BUFFER_FLUSH'),
        ('CLR_AUTO_EVENT'),
        ('REQUEST_FOR_DEADLOCK_SEARCH'),
        ('RESOURCE_QUEUE'),
        ('SERVER_IDLE_CHECK'),
        ('SLEEP_DBSTARTUP'),
        ('SLEEP_DBRECOVER'),
        ('SLEEP_DBTASK'),
        ('SLEEP_TEMPDBSTARTUP'),
        ('SNI_HTTP_ACCEPT'),
        ('DISPATCHER_QUEUE_SEMAPHORE'),
        ('BROKER_TO_FLUSH'),
        ('CHECKPOINT_QUEUE'),
        ('DBMIRROR_EVENTS_QUEUE'),
        ('SQLTRACE_INCREMENTAL_FLUSH_SLEEP'),
        ('WAIT_XTP_OFFLINE_CKPT_NEW_LOG'),
        ('HADR_WORK_QUEUE'),
        ('HADR_FILESTREAM_IOMGR_IOCOMPLETION'),
        ('HADR_WORK_POOL_WAIT'),
        ('XE_DISPATCHER_WAIT'),
        ('XE_TIMER_EVENT'),
        ('WAITFOR'),
        ('BROKER_EVENTHANDLER'),
        ('SLEEP_MASTERMDREADY'),
        ('SLEEP_MASTERUPGRADED'),
        ('SLEEP_MSDBSTARTUP'),
        ('SLEEP_SYSTEMTASK'),
        ('SLEEP_TEMPDBSTARTUP'),
        ('SNI_HTTP_ACCEPT'),
        ('REDO_THREAD_PENDING_WORK'),
        ('FT_IFTS_SCHEDULER_IDLE_WAIT'),
        ('DIRTY_PAGE_POLL'),
        ('HADR_FILESTREAM_IOMGR_IOCOMPLETION'),
        ('XIO_IDLE')
    ) AS v (wait_type)
),
FilteredWaits AS (
    SELECT
        ws.wait_type,
        ws.waiting_tasks_count,
        ws.wait_time_ms,
        ws.signal_wait_time_ms,
        ws.wait_time_ms - ws.signal_wait_time_ms AS resource_wait_time_ms,
        ws.max_wait_time_ms
    FROM sys.dm_os_wait_stats AS ws
    WHERE ws.wait_time_ms > 0
      AND ws.wait_type NOT IN (SELECT wait_type FROM BenignWaits)
      AND ws.wait_type NOT LIKE 'SLEEP_%'
      AND ws.wait_type NOT LIKE 'SQLTRACE_%'
      AND ws.wait_type NOT LIKE 'DBMIRROR_%'
),
WaitsWithPct AS (
    SELECT
        wait_type,
        waiting_tasks_count                                                     AS WaitingTasksCount,
        wait_time_ms                                                            AS WaitTimeMs,
        CASE WHEN waiting_tasks_count > 0
             THEN CAST(wait_time_ms * 1.0 / waiting_tasks_count AS DECIMAL(18,2))
             ELSE 0 END                                                         AS AvgWaitMs,
        signal_wait_time_ms                                                     AS SignalWaitTimeMs,
        resource_wait_time_ms                                                   AS ResourceWaitTimeMs,
        max_wait_time_ms                                                        AS MaxWaitTimeMs,
        CAST(wait_time_ms * 100.0 / NULLIF(SUM(wait_time_ms) OVER (), 0)
             AS DECIMAL(10,2))                                                  AS WaitPct,
        signal_wait_time_ms,
        wait_time_ms
    FROM FilteredWaits
)
SELECT
    w.wait_type                                                                 AS WaitType,
    w.WaitingTasksCount,
    w.WaitTimeMs,
    w.AvgWaitMs,
    w.SignalWaitTimeMs,
    w.ResourceWaitTimeMs,
    w.MaxWaitTimeMs,
    w.WaitPct,
    CASE
        -- CPU pressure: high signal waits or scheduler waits
        WHEN w.wait_type IN ('SOS_SCHEDULER_YIELD','THREADPOOL')
          OR (w.WaitTimeMs > 0 AND w.SignalWaitTimeMs * 1.0 / NULLIF(w.WaitTimeMs,0) > 0.70)
            THEN 'CPU'
        -- IO waits
        WHEN w.wait_type LIKE 'PAGEIOLATCH_%'
          OR w.wait_type IN ('IO_COMPLETION','ASYNC_IO_COMPLETION','WRITE_COMPLETION')
            THEN 'IO'
        -- Lock waits
        WHEN w.wait_type LIKE 'LCK_%'
            THEN 'LOCK'
        -- Log waits
        WHEN w.wait_type IN ('WRITELOG','LOGBUFFER','LOG_RATE_GOVERNOR')
            THEN 'LOG'
        -- Memory waits
        WHEN w.wait_type IN ('RESOURCE_SEMAPHORE','RESOURCE_SEMAPHORE_QUERY_COMPILE','CMEMTHREAD')
            THEN 'MEMORY'
        -- Network waits
        WHEN w.wait_type IN ('ASYNC_NETWORK_IO','NET_WAITFOR_PACKET')
            THEN 'NETWORK'
        -- Backup waits
        WHEN w.wait_type IN ('BACKUP','BACKUP_OPERATOR','BACKUPBUFFER','BACKUPIO','BACKUPTHREAD')
          OR w.wait_type LIKE 'BACKUP%'
            THEN 'BACKUP'
        -- Availability Group waits
        WHEN w.wait_type LIKE 'HADR_%'
          OR w.wait_type = 'DBMIRRORING_CMD'
            THEN 'AG'
        -- Parallelism waits
        WHEN w.wait_type IN ('CXPACKET','CXCONSUMER','EXCHANGE')
            THEN 'PARALLELISM'
        -- Worker thread waits
        WHEN w.wait_type = 'THREADPOOL'
            THEN 'WORKER_THREAD'
        ELSE 'OTHER'
    END                                                                         AS WaitCategory,
    -- Context
    DATEDIFF(MINUTE, sqlserver_start_time, GETDATE())                          AS UptimeMinutes,
    sqlserver_start_time                                                        AS SqlServerStartTime,
    GETDATE()                                                                   AS CollectedAt
FROM WaitsWithPct AS w
CROSS JOIN (SELECT sqlserver_start_time FROM sys.dm_os_sys_info) AS si
ORDER BY w.WaitPct DESC;
