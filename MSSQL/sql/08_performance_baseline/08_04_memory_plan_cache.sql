-- =============================================================================
-- 08_04_memory_plan_cache.sql — Memory and Plan Cache Analysis
-- Chapter 8: Performance Baseline
-- Description: Analyses plan cache composition, eviction pressure, memory
--              grant usage, and spill-prone queries.
-- Requires:    SQL Server 2016 or later (version guard below)
-- Note:        total_spills column requires SQL Server 2016+; wrapped in
--              version guard accordingly.
-- =============================================================================

IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning];
    RETURN;
END
GO

-- ── Section A: Plan cache overview ────────────────────────────────────────────
SELECT
    COUNT(*)                                                        AS TotalCachedPlans,
    SUM(CASE WHEN cp.usecounts = 1
              AND cp.objtype = 'Adhoc' THEN 1 ELSE 0 END)         AS SingleUseAdhocPlans,
    SUM(CASE WHEN cp.usecounts > 1 THEN 1 ELSE 0 END)             AS MultiUsePlans,
    SUM(CASE WHEN cp.objtype = 'Adhoc' THEN 1 ELSE 0 END)         AS TotalAdhocPlans,
    CAST(SUM(CAST(cp.size_in_bytes AS BIGINT)) / 1048576.0 AS DECIMAL(18,2))      AS TotalCacheSizeMB,
    CAST(SUM(CASE WHEN cp.usecounts = 1
                   AND cp.objtype = 'Adhoc'
                   THEN CAST(cp.size_in_bytes AS BIGINT) ELSE 0 END) / 1048576.0
         AS DECIMAL(18,2))                                          AS SingleUseAdhocCacheSizeMB,
    CAST(SUM(CASE WHEN cp.objtype = 'Adhoc'
                   THEN CAST(cp.size_in_bytes AS BIGINT) ELSE 0 END) / 1048576.0
         AS DECIMAL(18,2))                                          AS TotalAdhocCacheSizeMB,
    -- 'optimize for ad hoc workloads' setting
    (SELECT CAST(value_in_use AS BIT)
     FROM sys.configurations
     WHERE name = 'optimize for ad hoc workloads')                 AS OptimizeForAdhocWorkloads,
    GETDATE()                                                       AS CollectedAt
FROM sys.dm_exec_cached_plans AS cp;

-- ── Section B: Plan cache by object type ─────────────────────────────────────
SELECT
    cp.objtype                                                      AS PlanType,
    COUNT(*)                                                        AS PlanCount,
    SUM(CAST(cp.usecounts AS BIGINT))                               AS TotalUseCounts,
    CAST(SUM(CAST(cp.size_in_bytes AS BIGINT)) / 1048576.0 AS DECIMAL(18,2))      AS CacheSizeMB,
    CAST(AVG(CAST(cp.size_in_bytes AS BIGINT)) / 1024.0 AS DECIMAL(18,2))         AS AvgPlanSizeKB,
    GETDATE()                                                       AS CollectedAt
FROM sys.dm_exec_cached_plans AS cp
GROUP BY cp.objtype
ORDER BY CacheSizeMB DESC;

-- ── Section C: Plan eviction pressure ─────────────────────────────────────────
SELECT
    mc.name                             AS CacheStoreName,
    mc.type                             AS CacheStoreType,
    mc.pages_kb                         AS PagesKB,
    mc.pages_in_use_kb                  AS PagesInUseKB,
    mc.entries_count                    AS EntriesCount,
    mc.entries_in_use_count             AS EntriesInUseCount,
    GETDATE()                           AS CollectedAt
FROM sys.dm_os_memory_cache_counters AS mc
WHERE mc.name IN ('SQL Plans', 'Object Plans', 'Bound Trees', 'Extended Stored Procedures')
ORDER BY mc.pages_kb DESC;

-- ── Section D: Current memory grants ──────────────────────────────────────────
SELECT
    mg.session_id                                                   AS SessionId,
    mg.request_id                                                   AS RequestId,
    mg.scheduler_id                                                 AS SchedulerId,
    mg.grant_time                                                   AS GrantTime,
    mg.requested_memory_kb / 1024                                   AS RequestedMemoryMB,
    mg.granted_memory_kb / 1024                                     AS GrantedMemoryMB,
    mg.used_memory_kb / 1024                                        AS UsedMemoryMB,
    mg.max_used_memory_kb / 1024                                    AS MaxUsedMemoryMB,
    mg.ideal_memory_kb / 1024                                       AS IdealMemoryMB,
    mg.query_cost                                                   AS EstimatedQueryCost,
    mg.queue_id                                                     AS QueueId,
    mg.wait_order                                                   AS WaitOrder,
    CASE WHEN mg.grant_time IS NULL THEN 1 ELSE 0 END               AS IsPending,
    LEFT(st.text, 512)                                              AS SqlTextSnippet,
    GETDATE()                                                       AS CollectedAt
FROM sys.dm_exec_query_memory_grants AS mg
OUTER APPLY sys.dm_exec_sql_text(mg.sql_handle) AS st
ORDER BY mg.requested_memory_kb DESC;

-- Memory grant aggregate
SELECT
    COUNT(CASE WHEN grant_time IS NULL THEN 1 END)                  AS PendingGrantCount,
    COUNT(CASE WHEN grant_time IS NOT NULL THEN 1 END)              AS ActiveGrantCount,
    CAST(MAX(requested_memory_kb) / 1024.0 AS DECIMAL(18,2))       AS MaxRequestedMemoryMB,
    CAST(MAX(max_used_memory_kb) / 1024.0 AS DECIMAL(18,2))        AS MaxUsedMemoryMB,
    CAST(SUM(granted_memory_kb) / 1024.0 AS DECIMAL(18,2))         AS TotalGrantedMemoryMB,
    GETDATE()                                                       AS CollectedAt
FROM sys.dm_exec_query_memory_grants;

-- ── Section E: Spill-prone queries (SQL 2016+) ────────────────────────────────
-- total_spills column is available from SQL Server 2016 (version 13)
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) >= 13
BEGIN
    SELECT TOP 20
        qs.total_spills                                             AS TotalSpills,
        qs.total_spills / NULLIF(qs.execution_count, 0)            AS AvgSpillsPerExec,
        qs.execution_count                                          AS ExecutionCount,
        qs.total_worker_time / 1000                                 AS TotalCpuMs,
        qs.total_logical_reads                                      AS TotalLogicalReads,
        qs.total_logical_writes                                     AS TotalLogicalWrites,
        qs.total_elapsed_time / 1000                                AS TotalElapsedMs,
        qs.last_execution_time                                      AS LastExecutionTime,
        LEFT(st.text, 1000)                                         AS SqlText,
        qs.query_hash                                               AS QueryHash,
        qs.plan_handle                                              AS PlanHandle,
        GETDATE()                                                   AS CollectedAt
    FROM sys.dm_exec_query_stats AS qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
    WHERE qs.total_spills > 0
    ORDER BY qs.total_spills DESC;
END
