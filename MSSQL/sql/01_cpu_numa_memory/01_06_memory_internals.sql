-- =============================================================================
-- Chapter:      01 — CPU, NUMA, and Memory
-- Section:      01.06 — Memory Internals
-- Checklist:    1.6
-- Min Version:  SQL Server 2016 (v13)
-- Description:  Reports SQL Server internal memory distribution across three
--               views:
--                 1. Top 20 memory clerks by allocated pages (stolen memory).
--                 2. Buffer pool distribution by database (dirty vs clean pages).
--                 3. Page Life Expectancy (PLE) — overall and per NUMA node.
--                    PLE < 300 seconds flags a buffer pool under pressure.
-- =============================================================================

IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning];
    RETURN;
END
GO

SET NOCOUNT ON;

-- Top 20 memory clerks by allocated pages
SELECT TOP 20
    mc.type                                 AS ClerkType,
    mc.name                                 AS ClerkName,
    mc.memory_node_id                       AS MemoryNodeId,
    SUM(mc.pages_kb) / 1024                 AS AllocatedMB
FROM sys.dm_os_memory_clerks mc
GROUP BY mc.type, mc.name, mc.memory_node_id
ORDER BY SUM(mc.pages_kb) DESC;

-- Buffer pool distribution by database
SELECT
    ISNULL(DB_NAME(bd.database_id), 'ResourceDB')  AS DatabaseName,
    bd.database_id                                  AS DatabaseId,
    COUNT(*) * 8 / 1024                             AS BufferPoolMB,
    SUM(CAST(bd.is_modified AS INT)) * 8 / 1024     AS DirtyPagesMB,
    COUNT(*)                                        AS PageCount
FROM sys.dm_os_buffer_descriptors bd
GROUP BY bd.database_id
ORDER BY COUNT(*) DESC;

-- Page Life Expectancy — overall and per NUMA node
SELECT
    CASE
        WHEN pc.object_name LIKE '%Buffer Manager%' THEN 'Overall'
        ELSE 'NUMA_' + RTRIM(pc.instance_name)
    END                                     AS Scope,
    pc.cntr_value                           AS PLE_Seconds,
    CASE
        WHEN pc.cntr_value < 300            THEN 1
        ELSE 0
    END                                     AS flag_low_ple
FROM sys.dm_os_performance_counters pc
WHERE pc.counter_name = 'Page life expectancy'
  AND (   pc.object_name LIKE '%Buffer Manager%'
       OR pc.object_name LIKE '%Buffer Node%')
ORDER BY pc.object_name, pc.instance_name;
