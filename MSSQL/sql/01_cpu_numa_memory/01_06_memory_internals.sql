-- =============================================================================
-- Chapter:      01 — CPU, NUMA, and Memory
-- Section:      01.06 — Memory Internals
-- Checklist:    1.6
-- Min Version:  SQL Server 2016 (v13)
-- Description:  Six views of SQL Server internal memory distribution:
--                 1. Top 20 memory clerks by allocated pages — covers buffer
--                    pool, plan cache, lock manager, CLR, and other clerks.
--                 2. Buffer pool distribution by database (dirty vs clean).
--                 3. Page Life Expectancy — overall and per NUMA node.
--                    PLE < 300 seconds flags buffer pool pressure.
--                 4. Per-NUMA memory node allocation — local vs foreign memory,
--                    target vs actual, uneven distribution flag.
--                 5. Query memory grants — pending, active, excessive, and
--                    underused grants.
--                 6. RESOURCE_SEMAPHORE wait statistics — indicates memory
--                    grant queue pressure.
-- =============================================================================

IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning];
    RETURN;
END
GO

SET NOCOUNT ON;

-- ── 1. Top 20 memory clerks (includes lock manager, CLR, plan cache) ──────────
SELECT TOP 20
    mc.type                                     AS ClerkType,
    mc.name                                     AS ClerkName,
    mc.memory_node_id                           AS MemoryNodeId,
    SUM(mc.pages_kb) / 1024                     AS AllocatedMB,
    -- Categorise key clerk types
    CASE
        WHEN mc.type = 'MEMORYCLERK_SQLBUFFERPOOL'  THEN 'Buffer Pool'
        WHEN mc.type LIKE 'CACHESTORE%'             THEN 'Plan/Object Cache'
        WHEN mc.type = 'MEMORYCLERK_SQLCLR'         THEN 'CLR'
        WHEN mc.name = 'LOCK'                       THEN 'Lock Manager'
        WHEN mc.type LIKE '%LOCK%'                  THEN 'Lock Manager'
        WHEN mc.type = 'MEMORYCLERK_SQLTRACE'       THEN 'SQL Trace'
        WHEN mc.type LIKE '%XTP%'                   THEN 'In-Memory OLTP'
        ELSE 'Other'
    END                                         AS ClerkCategory
FROM sys.dm_os_memory_clerks mc
GROUP BY mc.type, mc.name, mc.memory_node_id
ORDER BY SUM(mc.pages_kb) DESC;

-- ── 2. Buffer pool by database ────────────────────────────────────────────────
SELECT
    ISNULL(DB_NAME(bd.database_id), 'ResourceDB')  AS DatabaseName,
    bd.database_id                                  AS DatabaseId,
    COUNT(*) * 8 / 1024                             AS BufferPoolMB,
    SUM(CAST(bd.is_modified AS INT)) * 8 / 1024     AS DirtyPagesMB,
    COUNT(*)                                        AS PageCount
FROM sys.dm_os_buffer_descriptors bd
GROUP BY bd.database_id
ORDER BY COUNT(*) DESC;

-- ── 3. Page Life Expectancy — overall and per NUMA node ───────────────────────
SELECT
    CASE
        WHEN pc.object_name LIKE '%Buffer Manager%' THEN 'Overall'
        ELSE 'NUMA_' + RTRIM(pc.instance_name)
    END                                         AS Scope,
    pc.cntr_value                               AS PLE_Seconds,
    CASE WHEN pc.cntr_value < 300               THEN 1 ELSE 0 END AS flag_low_ple
FROM sys.dm_os_performance_counters pc
WHERE pc.counter_name = 'Page life expectancy'
  AND (   pc.object_name LIKE '%Buffer Manager%'
       OR pc.object_name LIKE '%Buffer Node%')
ORDER BY pc.object_name, pc.instance_name;

-- ── 4. Per-NUMA memory node: local vs foreign allocation ──────────────────────
SELECT
    mn.memory_node_id                           AS MemoryNodeId,
    mn.pages_kb / 1024                          AS AllocatedMB,
    mn.target_kb / 1024                         AS TargetMB,
    mn.foreign_committed_kb / 1024              AS ForeignCommittedMB,
    mn.shared_memory_committed_kb / 1024        AS SharedCommittedMB,
    mn.locked_page_allocations_kb / 1024        AS LockedPagesMB,
    -- Pct of allocated memory that came from a foreign NUMA node
    CAST(
        mn.foreign_committed_kb * 100.0
        / NULLIF(mn.pages_kb, 0)
    AS DECIMAL(5,1))                            AS ForeignMemoryPct,
    -- Flag: > 10% of this node's memory is from a foreign NUMA node
    CASE
        WHEN mn.foreign_committed_kb > mn.pages_kb * 0.10
                                                THEN 1 ELSE 0
    END                                         AS flag_foreign_numa_memory,
    -- Flag: this node's allocation deviates > 25% from the average
    CASE
        WHEN node_count.NodeCount > 1
         AND ABS(
             CAST(mn.pages_kb AS FLOAT)
             / NULLIF(avg_alloc.AvgPagesKb, 0) - 1
         ) > 0.25                               THEN 1 ELSE 0
    END                                         AS flag_uneven_numa_memory
FROM sys.dm_os_memory_nodes mn
CROSS JOIN (
    SELECT AVG(CAST(pages_kb AS FLOAT)) AS AvgPagesKb
    FROM sys.dm_os_memory_nodes
    WHERE memory_node_id < 64
) avg_alloc
CROSS JOIN (
    SELECT COUNT(*) AS NodeCount
    FROM sys.dm_os_memory_nodes
    WHERE memory_node_id < 64
) node_count
WHERE mn.memory_node_id < 64          -- exclude the global/non-NUMA special node
ORDER BY mn.memory_node_id;

-- ── 5. Query memory grants — pending, active, excessive, underused ────────────
SELECT
    mg.session_id                               AS SessionId,
    mg.scheduler_id                             AS SchedulerId,
    mg.dop                                      AS Dop,
    mg.request_time                             AS RequestTime,
    mg.grant_time                               AS GrantTime,
    mg.requested_memory_kb / 1024               AS RequestedMB,
    mg.granted_memory_kb / 1024                 AS GrantedMB,
    mg.required_memory_kb / 1024                AS RequiredMB,
    mg.used_memory_kb / 1024                    AS UsedMB,
    mg.max_used_memory_kb / 1024                AS MaxUsedMB,
    mg.ideal_memory_kb / 1024                   AS IdealMB,
    mg.wait_time_ms                             AS WaitMs,
    mg.queue_id                                 AS QueueId,
    mg.is_next_candidate                        AS IsNextCandidate,
    -- Pending: grant not yet issued
    CASE WHEN mg.grant_time IS NULL             THEN 1 ELSE 0 END AS flag_grant_pending,
    -- Excessive: granted > 2x what was actually needed
    CASE
        WHEN mg.grant_time IS NOT NULL
         AND mg.max_used_memory_kb > 0
         AND mg.granted_memory_kb > mg.max_used_memory_kb * 2
                                                THEN 1 ELSE 0
    END                                         AS flag_excessive_grant,
    -- Underused: consumed < 50% of the granted memory
    CASE
        WHEN mg.grant_time IS NOT NULL
         AND mg.granted_memory_kb > 0
         AND mg.max_used_memory_kb < mg.granted_memory_kb * 0.5
                                                THEN 1 ELSE 0
    END                                         AS flag_underused_grant
FROM sys.dm_exec_query_memory_grants mg
ORDER BY mg.requested_memory_kb DESC;

-- ── 6. RESOURCE_SEMAPHORE waits ───────────────────────────────────────────────
SELECT
    w.wait_type                                 AS WaitType,
    w.waiting_tasks_count                       AS WaitingTasksCount,
    w.wait_time_ms                              AS TotalWaitMs,
    w.max_wait_time_ms                          AS MaxWaitMs,
    -- Flag: any RESOURCE_SEMAPHORE waits recorded since last restart
    CASE WHEN w.waiting_tasks_count > 0         THEN 1 ELSE 0 END AS flag_memory_grant_pressure
FROM sys.dm_os_wait_stats w
WHERE w.wait_type IN ('RESOURCE_SEMAPHORE', 'RESOURCE_SEMAPHORE_QUERY_COMPILE')
ORDER BY w.wait_type;
