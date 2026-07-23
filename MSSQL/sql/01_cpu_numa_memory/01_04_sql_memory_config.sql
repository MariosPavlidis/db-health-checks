-- =============================================================================
-- Chapter:      01 — CPU, NUMA, and Memory
-- Section:      01.04 — SQL Server Memory Configuration
-- Checklist:    1.4
-- Min Version:  SQL Server 2016 (v13)
-- Description:  Three views of SQL Server memory configuration:
--                 1. SQL Server configured limits, active memory model
--                    (CONVENTIONAL / LOCK_PAGES / LARGE_PAGES), current
--                    process memory, and OS headroom validation.
--                 2. Windows OS memory state — available physical memory,
--                    paging file state, and system memory pressure level.
--                 3. Pending memory configuration changes — settings where
--                    the configured value differs from the in-use value,
--                    indicating a reconfigure or restart is needed.
--
--               Flags:
--                 flag_max_mem_equals_host   — MaxServerMemoryMB >= host RAM,
--                                              no OS headroom
--                 flag_min_exceeds_max       — MinServerMemoryMB >= Max,
--                                              SQL cannot release memory
--                 flag_memory_pressure       — OS is signalling low memory
--                 flag_lpim_not_active       — sql_memory_model is not
--                                              LOCK_PAGES despite AWE enabled
--                 flag_pending_mem_change    — configured value not yet active
-- =============================================================================

IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning];
    RETURN;
END
GO

SET NOCOUNT ON;

-- ── 1. SQL Server memory configuration and process usage ──────────────────────
SELECT
    -- Configured limits
    minmem.value_in_use                             AS MinServerMemoryMB,
    maxmem.value_in_use                             AS MaxServerMemoryMB,
    awe.value_in_use                                AS AweEnabled,
    -- Memory model
    si.sql_memory_model                             AS MemoryModelCode,
    si.sql_memory_model_desc                        AS MemoryModel,
    -- Host physical memory
    si.physical_memory_kb / 1024                    AS HostPhysicalMemoryMB,
    -- Current SQL process memory
    pm.physical_memory_in_use_kb / 1024             AS SqlPhysicalMemoryUsedMB,
    pm.virtual_address_space_committed_kb / 1024    AS VasCommittedMB,
    pm.virtual_address_space_reserved_kb / 1024     AS VasReservedMB,
    pm.available_commit_limit_kb / 1024             AS AvailableCommitLimitMB,
    pm.memory_utilization_percentage                AS MemoryUtilizationPct,
    pm.process_physical_memory_low                  AS ProcessMemoryLow,
    pm.process_virtual_memory_low                   AS ProcessVirtualMemoryLow,
    -- Derived: OS headroom
    (si.physical_memory_kb / 1024) - maxmem.value_in_use
                                                    AS OsHeadroomMB,
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
          OR pm.process_virtual_memory_low  = 1     THEN 1 ELSE 0
    END                                             AS flag_memory_pressure,
    -- Flag: AWE enabled but LPIM not active (common misconfiguration)
    CASE
        WHEN awe.value_in_use = 1
         AND si.sql_memory_model <> 1               THEN 1 ELSE 0
    END                                             AS flag_lpim_not_active
FROM sys.configurations minmem
CROSS JOIN sys.configurations maxmem
CROSS JOIN sys.configurations awe
CROSS JOIN sys.dm_os_sys_info si
CROSS JOIN sys.dm_os_process_memory pm
WHERE minmem.name = 'min server memory (MB)'
  AND maxmem.name = 'max server memory (MB)'
  AND awe.name    = 'awe enabled';

-- ── 2. Windows OS memory state ────────────────────────────────────────────────
SELECT
    osm.total_physical_memory_kb / 1024         AS TotalPhysicalMemoryMB,
    osm.available_physical_memory_kb / 1024     AS AvailablePhysicalMemoryMB,
    CAST(
        (osm.total_physical_memory_kb
         - osm.available_physical_memory_kb) * 100.0
        / NULLIF(osm.total_physical_memory_kb, 0)
    AS DECIMAL(5,1))                            AS PhysicalMemoryUsedPct,
    osm.total_page_file_kb / 1024               AS TotalPageFileMB,
    osm.available_page_file_kb / 1024           AS AvailablePageFileMB,
    CAST(
        (osm.total_page_file_kb
         - osm.available_page_file_kb) * 100.0
        / NULLIF(osm.total_page_file_kb, 0)
    AS DECIMAL(5,1))                            AS PageFileUsedPct,
    osm.system_low_memory_signal_state          AS LowMemorySignalState,
    osm.system_high_memory_signal_state         AS HighMemorySignalState,
    osm.system_memory_state_desc                AS SystemMemoryState,
    -- Flag: OS is signalling low memory
    CASE
        WHEN osm.system_low_memory_signal_state = 1 THEN 1 ELSE 0
    END                                         AS flag_os_low_memory
FROM sys.dm_os_sys_memory osm;

-- ── 3. Pending memory configuration changes ───────────────────────────────────
SELECT
    c.name                                      AS ConfigName,
    c.value                                     AS ConfiguredValue,
    c.value_in_use                              AS ActiveValue,
    c.description                               AS Description,
    -- Flag: configured value not yet active — reconfigure or restart needed
    CASE WHEN c.value <> c.value_in_use         THEN 1 ELSE 0 END AS flag_pending_mem_change
FROM sys.configurations c
WHERE c.name IN (
    'min server memory (MB)',
    'max server memory (MB)',
    'awe enabled',
    'lock pages in memory'
)
  AND c.value <> c.value_in_use
ORDER BY c.name;
