-- =============================================================================
-- Health Check: Ch 06 TempDB — 6.6 Metadata and Allocation-Page Contention
-- Min SQL version: SQL Server 2016
--
-- Result sets:
--   1. Instance-level PAGELATCH wait totals
--   2. Current tempdb PAGELATCH waits classified as PFS/GAM/SGAM/metadata/other
--   3. Memory-optimized tempdb metadata state (SQL Server 2019+)
-- =============================================================================
SET NOCOUNT ON;

IF TRY_CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'VERSION_GUARD' AS ResultSetName,
           'Requires SQL Server 2016 or later.' AS Note;
    RETURN;
END;

-- ── 1. Cumulative PAGELATCH waits since instance start ───────────────────────
SELECT
    'PAGELATCH_WAIT_TOTALS'                             AS ResultSetName,
    wait_type                                          AS WaitType,
    waiting_tasks_count                                AS WaitingTasksCount,
    wait_time_ms                                       AS WaitTimeMs,
    signal_wait_time_ms                                AS SignalWaitTimeMs,
    CAST(wait_time_ms * 1.0 / NULLIF(waiting_tasks_count, 0)
         AS DECIMAL(18,2))                             AS AvgWaitMs,
    (SELECT sqlserver_start_time FROM sys.dm_os_sys_info)
                                                        AS CountersSince,
    CASE WHEN waiting_tasks_count >= 1000
           AND wait_time_ms >= 60000 THEN 1 ELSE 0 END AS flag_material_pagelatch_wait
FROM sys.dm_os_wait_stats
WHERE wait_type IN (N'PAGELATCH_SH', N'PAGELATCH_UP', N'PAGELATCH_EX')
ORDER BY wait_time_ms DESC;

-- ── 2. Current tempdb page-latch waits ───────────────────────────────────────
;WITH ParsedWaits AS
(
    SELECT
        wt.session_id,
        wt.exec_context_id,
        wt.wait_duration_ms,
        wt.wait_type,
        wt.blocking_session_id,
        wt.resource_description,
        TRY_CONVERT(INT, PARSENAME(REPLACE(wt.resource_description, ':', '.'), 3))
                                                         AS DatabaseId,
        TRY_CONVERT(INT, PARSENAME(REPLACE(wt.resource_description, ':', '.'), 2))
                                                         AS FileId,
        TRY_CONVERT(BIGINT, PARSENAME(REPLACE(wt.resource_description, ':', '.'), 1))
                                                         AS PageId
    FROM sys.dm_os_waiting_tasks AS wt
    WHERE wt.wait_type LIKE N'PAGELATCH[_]%'
      AND wt.resource_description LIKE N'2:%'
)
SELECT
    'CURRENT_TEMPDB_PAGELATCH'                          AS ResultSetName,
    pw.session_id                                       AS SessionId,
    pw.exec_context_id                                  AS ExecContextId,
    es.login_name                                       AS LoginName,
    es.host_name                                        AS HostName,
    es.program_name                                     AS ProgramName,
    pw.wait_type                                        AS WaitType,
    pw.wait_duration_ms                                 AS WaitDurationMs,
    pw.blocking_session_id                              AS BlockingSessionId,
    pw.resource_description                             AS ResourceDescription,
    pw.FileId,
    pw.PageId,
    CASE
        WHEN pw.PageId = 1 OR (pw.PageId > 1 AND (pw.PageId - 1) % 8088 = 0)
            THEN 'PFS'
        WHEN pw.PageId = 2 OR (pw.PageId > 2 AND (pw.PageId - 2) % 511232 = 0)
            THEN 'GAM'
        WHEN pw.PageId = 3 OR (pw.PageId > 3 AND (pw.PageId - 3) % 511232 = 0)
            THEN 'SGAM'
        WHEN pw.PageId IN (5, 7)
            THEN 'SYSTEM_METADATA'
        ELSE 'DATA_OR_OTHER'
    END                                                 AS ContentionClass,
    ib.event_info                                       AS LastSubmittedCommand,
    CASE
        WHEN pw.PageId = 1 OR (pw.PageId > 1 AND (pw.PageId - 1) % 8088 = 0)
          OR pw.PageId = 2 OR (pw.PageId > 2 AND (pw.PageId - 2) % 511232 = 0)
          OR pw.PageId = 3 OR (pw.PageId > 3 AND (pw.PageId - 3) % 511232 = 0)
            THEN 1 ELSE 0
    END                                                 AS flag_allocation_page_contention,
    CASE WHEN pw.PageId IN (5, 7) THEN 1 ELSE 0 END     AS flag_possible_metadata_contention
FROM ParsedWaits AS pw
LEFT JOIN sys.dm_exec_sessions AS es
    ON es.session_id = pw.session_id
OUTER APPLY sys.dm_exec_input_buffer(pw.session_id, NULL) AS ib
ORDER BY pw.wait_duration_ms DESC;

-- ── 3. Memory-optimized tempdb metadata state ────────────────────────────────
IF TRY_CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) >= 15
BEGIN
    SELECT
        'TEMPDB_METADATA_STATE'                           AS ResultSetName,
        TRY_CAST(SERVERPROPERTY('IsTempDbMetadataMemoryOptimized') AS INT)
                                                          AS IsMemoryOptimizedTempdbMetadata,
        (SELECT sqlserver_start_time FROM sys.dm_os_sys_info)
                                                          AS SqlServerStartTime,
        CASE
            WHEN TRY_CAST(SERVERPROPERTY('IsTempDbMetadataMemoryOptimized') AS INT) = 1
                THEN 'Enabled and active after the last SQL Server restart.'
            ELSE 'Disabled. Enable only when confirmed tempdb metadata contention materially affects workload.'
        END                                               AS Assessment,
        CASE
            WHEN TRY_CAST(SERVERPROPERTY('IsTempDbMetadataMemoryOptimized') AS INT) = 0
             AND EXISTS
                 (
                     SELECT 1
                     FROM sys.dm_os_waiting_tasks
                     WHERE wait_type LIKE N'PAGELATCH[_]%'
                       AND resource_description LIKE N'2:%'
                 )
                THEN 1 ELSE 0
        END                                               AS flag_review_metadata_optimization
    ;
END
ELSE
BEGIN
    SELECT
        'TEMPDB_METADATA_STATE' AS ResultSetName,
        'Memory-optimized tempdb metadata is available starting with SQL Server 2019.' AS Note;
END;
