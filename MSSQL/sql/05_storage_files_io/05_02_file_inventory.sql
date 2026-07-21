-- ============================================================
-- Health Check: Ch 05 Storage/Files/I/O — 5.2 File Inventory
-- Checklist ref: Section 5.2
-- Min SQL version: 2016 (130)
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- ── Result set 1: Master file inventory with growth and flag columns ───────────
-- Joins sys.master_files with sys.databases to get database name and
-- sys.filegroups (per-database) is not accessible from master context for all
-- databases; filegroup name is approximated for the log (type=1) and for data
-- files (type=0) via a known filegroup lookup in sys.master_files data_space_id.
-- The filegroup name for non-master databases is not directly queryable from
-- sys.master_files in the master database context, so we surface data_space_id
-- and note the limitation. For log files we return 'LOG' per convention.

SELECT
    d.name                                                          AS [DatabaseName],
    mf.name                                                         AS [LogicalFileName],
    mf.physical_name                                                AS [PhysicalPath],
    mf.type_desc                                                    AS [FileType],
    CASE
        WHEN mf.type = 1 THEN 'LOG'
        ELSE CAST(mf.data_space_id AS VARCHAR(10))
    END                                                             AS [FileGroupIdOrLog],
    -- SizeMB: size is in 8KB pages
    mf.size * 8 / 1024                                              AS [SizeMB],
    -- MaxSizeMB: -1 = unlimited (SQL uses -1 or 268435456 to mean unlimited)
    CASE
        WHEN mf.max_size = -1         THEN -1
        WHEN mf.max_size = 268435456  THEN -1
        ELSE mf.max_size * 8 / 1024
    END                                                             AS [MaxSizeMB],
    -- GrowthDisplay: show as percentage or MB
    CASE
        WHEN mf.is_percent_growth = 1
            THEN CAST(mf.growth AS VARCHAR(10)) + '%'
        ELSE CAST(mf.growth * 8 / 1024 AS VARCHAR(10)) + ' MB'
    END                                                             AS [GrowthDisplay],
    mf.is_percent_growth                                            AS [IsPercentGrowth],
    mf.growth                                                       AS [GrowthValue],
    mf.state_desc                                                   AS [StateDesc],
    mf.is_sparse                                                    AS [IsSparse],
    mf.database_id                                                  AS [DatabaseId],
    mf.file_id                                                      AS [FileId],
    -- ── Flag: FilesWithUnlimitedGrowth ──────────────────────────────────────
    -- Unlimited growth can exhaust disk space unexpectedly.
    CASE
        WHEN mf.max_size = -1 OR mf.max_size = 268435456 THEN 1
        ELSE 0
    END                                                             AS [FilesWithUnlimitedGrowth],
    -- ── Flag: FilesNearMaxSize ───────────────────────────────────────────────
    -- Current size > 90% of max_size (only applicable when max_size is set).
    CASE
        WHEN mf.max_size > 0
         AND mf.max_size NOT IN (-1, 268435456)
         AND mf.size > mf.max_size * 0.9
            THEN 1
        ELSE 0
    END                                                             AS [FilesNearMaxSize],
    -- ── Flag: SmallFixedGrowth ───────────────────────────────────────────────
    -- Fixed-increment growth < 128 MB on data files causes frequent small autogrowth
    -- events and significant performance impact under load.
    CASE
        WHEN mf.is_percent_growth = 0
         AND mf.type = 0
         AND mf.growth * 8 / 1024 < 128
         AND mf.growth > 0
            THEN 1
        ELSE 0
    END                                                             AS [SmallFixedGrowth],
    -- ── Flag: FilesUsingPercentGrowth ────────────────────────────────────────
    -- Percent growth leads to exponentially larger growths over time; fixed
    -- increments are generally preferred for predictability.
    CASE
        WHEN mf.is_percent_growth = 1 THEN 1
        ELSE 0
    END                                                             AS [FilesUsingPercentGrowth]
FROM sys.master_files AS mf
JOIN sys.databases    AS d
    ON d.database_id = mf.database_id
ORDER BY
    d.name,
    mf.type,
    mf.name;

GO

-- ── Result set 2: Per-file space usage via dm_db_file_space_usage ─────────────
-- sys.dm_db_file_space_usage is scoped to the current database, so we must
-- use dynamic SQL to query each online database individually.
-- Returns UsedSpaceMB and FreeInternalSpaceMB (allocated - used) per file.
-- Note: FreeInternalSpaceMB is space inside the allocated file extent that
-- SQL Server has not yet used; it does not represent disk free space.

DECLARE @sql    NVARCHAR(MAX) = N'';
DECLARE @dbName SYSNAME;

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM   sys.databases
    WHERE  state_desc = 'ONLINE'
      AND  is_read_only = 0  -- dm_db_file_space_usage may be unavailable on read-only databases
    ORDER BY name;

CREATE TABLE #FileSpaceUsage (
    DatabaseName        SYSNAME,
    FileId              INT,
    FileGroupId         INT,
    TotalExtentsMB      BIGINT,
    UsedExtentsMB       BIGINT,
    FreeInternalSpaceMB BIGINT
);

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @dbName;

WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        SET @sql = N'USE ' + QUOTENAME(@dbName) + N';
            INSERT INTO #FileSpaceUsage
            SELECT
                DB_NAME()                                       AS DatabaseName,
                file_id                                         AS FileId,
                filegroup_id                                    AS FileGroupId,
                total_page_count   * 8 / 1024                  AS TotalExtentsMB,
                allocated_extent_page_count * 8 / 1024         AS UsedExtentsMB,
                (total_page_count - allocated_extent_page_count) * 8 / 1024
                                                               AS FreeInternalSpaceMB
            FROM sys.dm_db_file_space_usage;';

        EXEC sp_executesql @sql;
    END TRY
    BEGIN CATCH
        -- Skip databases that error (e.g. in recovery, snapshot isolation issues)
        INSERT INTO #FileSpaceUsage (DatabaseName, FileId, FileGroupId, TotalExtentsMB, UsedExtentsMB, FreeInternalSpaceMB)
        VALUES (@dbName, -1, -1, -1, -1, -1);
    END CATCH;

    FETCH NEXT FROM db_cursor INTO @dbName;
END;

CLOSE db_cursor;
DEALLOCATE db_cursor;

-- Join with master_files to surface physical file path alongside usage
SELECT
    fu.DatabaseName,
    fu.FileId,
    fu.FileGroupId,
    mf.physical_name                                            AS [PhysicalPath],
    mf.type_desc                                                AS [FileType],
    fu.TotalExtentsMB,
    fu.UsedExtentsMB                                            AS [UsedSpaceMB],
    fu.FreeInternalSpaceMB
FROM #FileSpaceUsage fu
LEFT JOIN sys.master_files mf
    ON  mf.database_id = DB_ID(fu.DatabaseName)
    AND mf.file_id     = fu.FileId
ORDER BY
    fu.DatabaseName,
    fu.FileId;

DROP TABLE #FileSpaceUsage;

GO
