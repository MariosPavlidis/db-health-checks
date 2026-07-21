-- ============================================================
-- Health Check: Ch 02 Virtualization and Hypervisor — 02.1 Guest Virtualization Facts
-- Checklist ref: Section 2.1
-- Min SQL version: 2016 (130)
-- ============================================================
-- Queries sys.dm_os_sys_info and sys.dm_os_memory_nodes to surface
-- hypervisor detection, CPU/memory topology, soft-NUMA configuration,
-- large/locked page allocations, and NUMA node layout as seen by SQL Server.
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- Hypervisor / virtual machine detection
-- virtual_machine_type: 0=None (physical), 1=Hypervisor, 2=Other virtualization
-- large/locked page columns moved to sys.dm_os_process_memory in SQL Server 2025
SELECT
    si.virtual_machine_type                     AS VirtualMachineType,
    si.virtual_machine_type_desc                AS VirtualMachineTypeDesc,
    si.physical_memory_kb / 1024               AS PhysicalMemoryMB,
    si.cpu_count                               AS LogicalCPUCount,
    si.hyperthread_ratio                        AS HyperthreadRatio,
    si.cpu_count / si.hyperthread_ratio         AS PhysicalCoreCount,
    si.softnuma_configuration_desc              AS SoftNUMADesc,
    si.numa_node_count                          AS NUMANodeCount,
    -- Dynamic memory indicators
    -- large page allocations indicate static (non-dynamic) memory
    pm.large_page_allocations_kb / 1024         AS LargePagesMB,
    pm.locked_page_allocations_kb / 1024        AS LockedPagesMB,
    si.sqlserver_start_time                     AS LastStartTime
FROM sys.dm_os_sys_info si
CROSS JOIN sys.dm_os_process_memory pm;

GO

-- NUMA topology visible to guest (as seen by SQL Server)
SELECT
    memory_node_id                              AS MemoryNodeId,
    pages_kb / 1024                             AS NodePagesMB,
    virtual_address_space_reserved_kb / 1024    AS VASReservedMB
FROM sys.dm_os_memory_nodes
WHERE memory_node_id < 64
ORDER BY memory_node_id;
