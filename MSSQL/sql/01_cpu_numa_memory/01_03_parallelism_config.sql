-- =============================================================================
-- Chapter:      01 — CPU, NUMA, and Memory
-- Section:      01.03 — Parallelism Configuration
-- Checklist:    1.3
-- Min Version:  SQL Server 2016 (v13)
-- Description:  Reports MAXDOP and Cost Threshold for Parallelism at instance
--               level, alongside the logical CPU and NUMA node count needed to
--               evaluate the settings in context.
--
--               Flags:
--                 flag_maxdop_zero_many_cpus — MAXDOP = 0 on instances with
--                   more than 8 logical CPUs. Default unlimited parallelism is
--                   rarely appropriate at that scale.
--                 flag_ctp_default — Cost Threshold still at the factory
--                   default of 5, which is too low for most modern workloads.
-- =============================================================================

IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning];
    RETURN;
END
GO

SET NOCOUNT ON;

SELECT
    si.cpu_count                            AS LogicalCpuCount,
    si.socket_count                         AS SocketCount,
    si.cores_per_socket                     AS CoresPerSocket,
    si.numa_node_count                      AS NumaNodeCount,
    maxdop.value_in_use                     AS MaxDopEffective,
    maxdop.value                            AS MaxDopConfigured,
    ctp.value_in_use                        AS CostThresholdEffective,
    ctp.value                               AS CostThresholdConfigured,
    CASE
        WHEN maxdop.value_in_use = 0
         AND si.cpu_count > 8              THEN 1
        ELSE 0
    END                                     AS flag_maxdop_zero_many_cpus,
    CASE
        WHEN ctp.value_in_use = 5          THEN 1
        ELSE 0
    END                                     AS flag_ctp_default
FROM sys.configurations  maxdop
CROSS JOIN sys.configurations  ctp
CROSS JOIN sys.dm_os_sys_info  si
WHERE maxdop.name = 'max degree of parallelism'
  AND ctp.name   = 'cost threshold for parallelism';
