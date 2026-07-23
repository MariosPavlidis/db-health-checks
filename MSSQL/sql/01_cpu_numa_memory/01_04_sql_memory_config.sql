-- =============================================================================
-- Chapter:      01 — CPU, NUMA, and Memory
-- Section:      01.04 — SQL Server Memory Configuration
-- Checklist:    1.4
-- Min Version:  SQL Server 2016 (v13)
-- Description:  Reports min/max server memory settings, the active memory
--               model (CONVENTIONAL, LOCK_PAGES, LARGE_PAGES), host physical
--               memory, current SQL process memory consumption, and OS-level
--               memory pressure signals.
--
--               Flags:
--                 flag_max_mem_equals_host — MaxServerMemoryMB is set to or
--                   above total host RAM, leaving no headroom for the OS.
--                 flag_min_exceeds_max — MinServerMemoryMB >= MaxServerMemoryMB,
--                   which prevents SQL Server from releasing memory.
--                 flag_memory_pressure — SQL Server is currently reporting low
--                   physical or virtual address space from the OS.
-- =============================================================================

IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning];
    RETURN;
END
GO

SET NOCOUNT ON;

SELECT
    -- Configured limits
    minmem.value_in_use                             AS MinServerMemoryMB,
    maxmem.value_in_use                             AS MaxServerMemoryMB,
    awe.value_in_use                                AS AweEnabled,
    -- Memory model
    si.sql_memory_model_desc                        AS MemoryModel,
    -- Host physical memory
    si.physical_memory_kb / 1024                    AS HostPhysicalMemoryMB,
    -- Current SQL process memory
    pm.physical_memory_in_use_kb / 1024             AS SqlPhysicalMemoryUsedMB,
    pm.virtual_address_space_committed_kb / 1024    AS VasCommittedMB,
    pm.virtual_address_space_reserved_kb / 1024     AS VasReservedMB,
    pm.memory_utilization_percentage                AS MemoryUtilizationPct,
    pm.process_physical_memory_low                  AS ProcessMemoryLow,
    pm.process_virtual_memory_low                   AS ProcessVirtualMemoryLow,
    -- Flags
    CASE
        WHEN maxmem.value_in_use >= si.physical_memory_kb / 1024
         THEN 1 ELSE 0
    END                                             AS flag_max_mem_equals_host,
    CASE
        WHEN minmem.value_in_use > 0
         AND minmem.value_in_use >= maxmem.value_in_use
         THEN 1 ELSE 0
    END                                             AS flag_min_exceeds_max,
    CASE
        WHEN pm.process_physical_memory_low = 1
          OR pm.process_virtual_memory_low  = 1
         THEN 1 ELSE 0
    END                                             AS flag_memory_pressure
FROM sys.configurations     minmem
CROSS JOIN sys.configurations maxmem
CROSS JOIN sys.configurations awe
CROSS JOIN sys.dm_os_sys_info si
CROSS JOIN sys.dm_os_process_memory pm
WHERE minmem.name = 'min server memory (MB)'
  AND maxmem.name = 'max server memory (MB)'
  AND awe.name    = 'awe enabled';
