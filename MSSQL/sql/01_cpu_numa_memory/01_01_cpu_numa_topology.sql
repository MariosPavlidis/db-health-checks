-- =============================================================================
-- Chapter:      01 — CPU, NUMA, and Memory
-- Section:      01.01 — CPU and NUMA Topology
-- Checklist:    1.1
-- Min Version:  SQL Server 2016 (v13)
-- Description:  Collects full CPU and NUMA topology from SQL Server's
--               perspective:
--                 • Logical CPU count, physical cores, sockets, cores/socket,
--                   hyperthread ratio, total and online scheduler counts.
--                 • Soft-NUMA configuration and processor group layout.
--                 • Per-NUMA node: scheduler count, memory node mapping,
--                   visible/hidden/background scheduler breakdown.
--                 • Scheduler-to-memory-node mapping to detect misalignment.
--                 • Flags for uneven CPU distribution across NUMA nodes and
--                   vNUMA guest topology mismatches.
-- =============================================================================

IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning];
    RETURN;
END
GO

SET NOCOUNT ON;

-- ── 1. Instance-level CPU and NUMA summary ────────────────────────────────────
SELECT
    cpu_count                               AS LogicalCpuCount,
    hyperthread_ratio                       AS HyperthreadRatio,
    cpu_count / NULLIF(hyperthread_ratio, 0)AS PhysicalCoreCount,
    socket_count                            AS SocketCount,
    cores_per_socket                        AS CoresPerSocket,
    numa_node_count                         AS NumaNodeCount,
    scheduler_count                         AS OnlineSchedulerCount,
    scheduler_total_count                   AS TotalSchedulerCount,
    max_workers_count                       AS MaxWorkers,
    softnuma_configuration                  AS SoftNumaConfigCode,
    softnuma_configuration_desc             AS SoftNumaConfig,
    virtual_machine_type                    AS VmTypeCode,
    virtual_machine_type_desc               AS VirtualMachineType,
    sql_memory_model_desc                   AS MemoryModel,
    -- Flag: soft-NUMA is active (manual or automatic)
    CASE WHEN softnuma_configuration > 0    THEN 1 ELSE 0 END  AS flag_softnuma_active,
    -- Flag: running inside a hypervisor — validate vNUMA alignment manually
    CASE WHEN virtual_machine_type > 0      THEN 1 ELSE 0 END  AS flag_is_virtual
FROM sys.dm_os_sys_info;

-- ── 2. Per-NUMA node: layout, memory node mapping, scheduler counts ───────────
SELECT
    n.node_id                                       AS NumaNodeId,
    n.node_state_desc                               AS NodeState,
    n.memory_node_id                                AS MemoryNodeId,
    n.processor_group                               AS ProcessorGroup,
    n.online_scheduler_count                        AS OnlineSchedulers,
    n.idle_scheduler_count                          AS IdleSchedulers,
    n.active_worker_count                           AS ActiveWorkers,
    n.avg_load_balance                              AS AvgLoadBalance,
    -- Counts from sys.dm_os_schedulers for this NUMA node
    sched.TotalSchedulers,
    sched.VisibleOnline,
    sched.VisibleOffline,
    sched.Hidden,
    sched.Background,
    -- Flag: CPU node and memory node IDs do not match (NUMA imbalance risk)
    CASE WHEN n.node_id <> n.memory_node_id         THEN 1 ELSE 0 END AS flag_node_memory_mismatch,
    -- Flag: node has no online schedulers
    CASE WHEN n.online_scheduler_count = 0          THEN 1 ELSE 0 END AS flag_no_online_schedulers
FROM sys.dm_os_nodes n
OUTER APPLY (
    SELECT
        COUNT(*)                                                            AS TotalSchedulers,
        SUM(CASE WHEN s.status = 'VISIBLE ONLINE'   THEN 1 ELSE 0 END)    AS VisibleOnline,
        ISNULL(SUM(CASE WHEN s.status = 'VISIBLE OFFLINE' THEN 1 ELSE 0 END), 0) AS VisibleOffline,
        SUM(CASE WHEN s.status LIKE 'HIDDEN%'       THEN 1 ELSE 0 END)    AS Hidden,
        SUM(CASE WHEN s.is_idle = 1                 THEN 1 ELSE 0 END)    AS Background
    FROM sys.dm_os_schedulers s
    WHERE s.parent_node_id = n.node_id
) sched
WHERE n.node_state_desc <> 'ONLINE DAC'
ORDER BY n.node_id;

-- ── 3. Scheduler-to-memory-node mapping ──────────────────────────────────────
--    Shows each NUMA-node/memory-node combination and scheduler counts.
--    Rows where NumaNodeId != MemoryNodeId indicate cross-node mapping.
--    memory_node_id comes from sys.dm_os_nodes (not dm_os_schedulers).
SELECT
    s.parent_node_id                        AS NumaNodeId,
    n.memory_node_id                        AS MemoryNodeId,
    s.status                                AS SchedulerStatus,
    COUNT(*)                                AS SchedulerCount,
    SUM(s.current_workers_count)            AS CurrentWorkers,
    SUM(s.active_workers_count)             AS ActiveWorkers,
    -- Flag: schedulers on this NUMA node are mapped to a different memory node
    CASE WHEN s.parent_node_id <> n.memory_node_id THEN 1 ELSE 0 END AS flag_cross_node_mapping
FROM sys.dm_os_schedulers s
JOIN sys.dm_os_nodes n
    ON  n.node_id = s.parent_node_id
WHERE s.scheduler_id < 255
  AND n.node_state_desc <> 'ONLINE DAC'
GROUP BY s.parent_node_id, n.memory_node_id, s.status
ORDER BY s.parent_node_id, n.memory_node_id, s.status;

-- ── 4. Uneven CPU distribution across NUMA nodes ─────────────────────────────
--    Compares online schedulers per node against the average.
--    Imbalance > 25 % from the mean flags a potential soft-NUMA or
--    affinity mask misconfiguration.
SELECT
    n.node_id                                   AS NumaNodeId,
    n.online_scheduler_count                    AS OnlineSchedulers,
    avg_schedulers.AvgSchedulers,
    CAST(n.online_scheduler_count AS FLOAT)
        / NULLIF(avg_schedulers.AvgSchedulers, 0)
                                                AS RatioToAvg,
    CASE
        WHEN avg_schedulers.NodeCount > 1
         AND ABS(CAST(n.online_scheduler_count AS FLOAT)
             / NULLIF(avg_schedulers.AvgSchedulers, 0) - 1) > 0.25
                                                THEN 1
        ELSE 0
    END                                         AS flag_uneven_distribution
FROM sys.dm_os_nodes n
CROSS JOIN (
    SELECT
        AVG(CAST(online_scheduler_count AS FLOAT))  AS AvgSchedulers,
        COUNT(*)                                    AS NodeCount
    FROM sys.dm_os_nodes
    WHERE node_state_desc <> 'ONLINE DAC'
      AND online_scheduler_count > 0
) avg_schedulers
WHERE n.node_state_desc <> 'ONLINE DAC'
ORDER BY n.node_id;
