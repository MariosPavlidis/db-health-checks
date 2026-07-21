-- ============================================================
-- Health Check: Ch 06 TempDB — 6.3 TempDB Performance Indicators
-- Checklist ref: Section 6.3
-- Min SQL version: 2016 (130)
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- ── Part 1: TempDB I/O latency per file ───────────────────────────────────────
-- dm_io_virtual_file_stats(db_id, file_id): passing NULL for file_id returns all files.
-- Only database_id = 2 (TempDB) rows are relevant here.
SELECT
    vfs.database_id,
    mf.name                                         AS LogicalName,
    mf.physical_name                                AS PhysicalPath,
    mf.type_desc                                    AS FileTypeDesc,
    vfs.io_stall_read_ms,
    vfs.num_of_reads,
    CASE WHEN vfs.num_of_reads = 0 THEN 0
         ELSE vfs.io_stall_read_ms / vfs.num_of_reads
    END                                             AS AvgReadLatencyMs,
    vfs.io_stall_write_ms,
    vfs.num_of_writes,
    CASE WHEN vfs.num_of_writes = 0 THEN 0
         ELSE vfs.io_stall_write_ms / vfs.num_of_writes
    END                                             AS AvgWriteLatencyMs,
    vfs.io_stall,
    vfs.num_of_bytes_read,
    vfs.num_of_bytes_written,
    -- Cumulative since last SQL restart — note in header
    'Cumulative since SQL Server start; baseline against prior collection' AS LatencyNote
FROM sys.dm_io_virtual_file_stats(2, NULL)          vfs
JOIN sys.master_files                               mf
    ON  mf.database_id = vfs.database_id
    AND mf.file_id     = vfs.file_id
ORDER BY mf.type_desc, mf.file_id;

GO

-- ── Part 2: PAGELATCH contention on TempDB allocation pages ───────────────────
-- Resource description format: <db_id>:<file_id>:<page_no>
-- PFS pages : page 1, then every 8088 pages (1, 8089, 16177, ...)
-- GAM pages : page 2, then every 511232 pages
-- SGAM pages: page 3, then every 511232 pages
SELECT
    wt.wait_type,
    wt.resource_description,
    wt.wait_duration_ms,
    wt.blocking_session_id,
    wt.session_id,
    wt.exec_context_id,
    -- Parse file_id from resource description  (<db>:<file>:<page>)
    CAST(PARSENAME(REPLACE(wt.resource_description, ':', '.'), 2) AS INT)   AS FileId,
    -- Parse page_no
    CAST(PARSENAME(REPLACE(wt.resource_description, ':', '.'), 1) AS INT)   AS PageNo,
    -- Classify allocation page type
    CASE
        WHEN CAST(PARSENAME(REPLACE(wt.resource_description, ':', '.'), 1) AS INT)
             IN (1, 3, 5, 7)
          OR CAST(PARSENAME(REPLACE(wt.resource_description, ':', '.'), 1) AS INT) % 8088 = 1
            THEN 'PFS'
        WHEN CAST(PARSENAME(REPLACE(wt.resource_description, ':', '.'), 1) AS INT) = 2
          OR CAST(PARSENAME(REPLACE(wt.resource_description, ':', '.'), 1) AS INT) % 511232 = 2
            THEN 'GAM'
        WHEN CAST(PARSENAME(REPLACE(wt.resource_description, ':', '.'), 1) AS INT) = 3
          OR CAST(PARSENAME(REPLACE(wt.resource_description, ':', '.'), 1) AS INT) % 511232 = 3
            THEN 'SGAM'
        ELSE 'Data/Other'
    END                                                                      AS PageType,
    -- Advisory: if PFS/GAM/SGAM contention appears, consider adding TempDB data files
    CASE
        WHEN CAST(PARSENAME(REPLACE(wt.resource_description, ':', '.'), 1) AS INT)
             IN (1, 2, 3)
          OR CAST(PARSENAME(REPLACE(wt.resource_description, ':', '.'), 1) AS INT) % 8088 = 1
            THEN 'Allocation page contention — consider equal-sized TempDB data files (1 per scheduler core, max 8)'
        ELSE ''
    END                                                                      AS Advisory
FROM sys.dm_os_waiting_tasks                        wt
WHERE wt.wait_type LIKE 'PAGELATCH%'
  AND wt.resource_description LIKE '2:%'
ORDER BY wt.wait_duration_ms DESC;

GO

-- ── Part 3: Top 20 queries causing sort/hash spills to TempDB ─────────────────
-- total_spills available from SQL Server 2016+ (build 13.0.4001+)
-- A spill indicates insufficient memory grant; tuning or MAXDOP/MAXRECURSION may help.
SELECT TOP 20
    qs.total_spills,
    qs.min_spills,
    qs.max_spills,
    qs.execution_count,
    CAST(qs.total_spills * 1.0 / NULLIF(qs.execution_count, 0) AS DECIMAL(18,2))
                                                    AS AvgSpillsPerExecution,
    qs.total_worker_time,
    CAST(qs.total_worker_time * 1.0 / NULLIF(qs.execution_count, 0) AS DECIMAL(18,0))
                                                    AS AvgWorkerTimeUs,
    qs.total_elapsed_time,
    CAST(qs.total_elapsed_time * 1.0 / NULLIF(qs.execution_count, 0) AS DECIMAL(18,0))
                                                    AS AvgElapsedTimeUs,
    qs.total_logical_reads,
    qs.total_logical_writes,
    qs.creation_time                                AS PlanCacheTime,
    qs.last_execution_time,
    SUBSTRING(st.text, (qs.statement_start_offset / 2) + 1,
        ((CASE qs.statement_end_offset
              WHEN -1 THEN DATALENGTH(st.text)
              ELSE qs.statement_end_offset
          END - qs.statement_start_offset) / 2) + 1)
                                                    AS SqlText,
    qs.query_hash,
    qs.query_plan_hash
FROM sys.dm_exec_query_stats                        qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle)    st
WHERE qs.total_spills > 0
ORDER BY qs.total_spills DESC;

GO

-- ── Part 4: TempDB autogrowth events from default trace ───────────────────────
-- Event 92 = Data File Auto Grow, Event 93 = Log File Auto Grow
-- Only returns results if the default trace is enabled and covers recent history.
DECLARE @tracePath NVARCHAR(512);
SELECT @tracePath = path FROM sys.traces WHERE is_default = 1;

IF @tracePath IS NOT NULL
BEGIN
    SELECT
        ftc.StartTime,
        ftc.EndTime,
        ftc.DatabaseName,
        ftc.Filename,
        ftc.Duration        / 1000                  AS DurationMs,
        ftc.IntegerData     * 8 / 1024              AS GrowthMB,
        CASE ftc.EventClass
            WHEN 92 THEN 'Data File Auto Grow'
            WHEN 93 THEN 'Log File Auto Grow'
            ELSE 'Other'
        END                                         AS EventType,
        'Default Trace'                             AS Source
    FROM sys.fn_trace_gettable(@tracePath, DEFAULT) ftc
    WHERE ftc.EventClass IN (92, 93)
      AND ftc.DatabaseID  = 2          -- TempDB only
    ORDER BY ftc.StartTime DESC;
END
ELSE
BEGIN
    SELECT 'Default trace is not enabled or path not found' AS [Note];
END
