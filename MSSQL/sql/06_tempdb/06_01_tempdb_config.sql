-- ============================================================
-- Health Check: Ch 06 TempDB — 6.1 TempDB File Configuration
-- Checklist ref: Section 6.1
-- Min SQL version: 2016 (130)
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- ── Part 1: TempDB file inventory with sizing validation flags ─────────────────
--
-- Flags:
--   EqualDataFileSizes    : Y if all data files share the same size, N otherwise
--   EqualGrowthSettings   : Y if all data files share the same growth value and growth type, N otherwise
--   UndersizedFile        : Y if this data file is smaller than half the average size of other data files
--   PreSizingNote         : Reminder to pre-size files before workload peaks

;WITH FileInfo AS (
    SELECT
        mf.file_id,
        mf.name                                         AS LogicalName,
        mf.physical_name                                AS PhysicalPath,
        mf.type_desc                                    AS FileTypeDesc,
        CAST(mf.size * 8.0 / 1024 AS DECIMAL(18,2))    AS SizeMB,
        CASE mf.max_size
            WHEN -1 THEN -1          -- unlimited
            WHEN  0 THEN  0          -- no growth
            ELSE CAST(mf.max_size * 8.0 / 1024 AS DECIMAL(18,2))
        END                                             AS MaxSizeMB,
        CASE
            WHEN mf.is_percent_growth = 1
                THEN CAST(mf.growth AS VARCHAR(10)) + '%'
            ELSE CAST(CAST(mf.growth * 8.0 / 1024 AS DECIMAL(18,2)) AS VARCHAR(20)) + ' MB'
        END                                             AS GrowthSetting,
        mf.is_percent_growth                            AS IsPercentGrowth,
        mf.state_desc                                   AS StateDesc
    FROM sys.master_files mf
    WHERE mf.database_id = 2   -- TempDB
),
DataFiles AS (
    SELECT * FROM FileInfo WHERE FileTypeDesc = 'ROWS'
),
DataFileStats AS (
    SELECT
        COUNT(*)                    AS DataFileCount,
        AVG(SizeMB)                 AS AvgDataSizeMB,
        MIN(SizeMB)                 AS MinDataSizeMB,
        MAX(SizeMB)                 AS MaxDataSizeMB,
        MIN(GrowthSetting)          AS MinGrowth,
        MAX(GrowthSetting)          AS MaxGrowth,
        MIN(CAST(IsPercentGrowth AS TINYINT)) AS MinPctGrowth,
        MAX(CAST(IsPercentGrowth AS TINYINT)) AS MaxPctGrowth
    FROM DataFiles
),
LogFiles AS (
    SELECT COUNT(*) AS LogFileCount FROM FileInfo WHERE FileTypeDesc = 'LOG'
)
SELECT
    fi.file_id,
    fi.LogicalName,
    fi.PhysicalPath,
    fi.FileTypeDesc,
    fi.SizeMB,
    fi.MaxSizeMB,
    fi.GrowthSetting,
    fi.IsPercentGrowth,
    fi.StateDesc,
    -- Aggregate counts
    dfs.DataFileCount,
    lf.LogFileCount,
    -- Equal sizing flag (data files only; N/A for log)
    CASE
        WHEN fi.FileTypeDesc <> 'ROWS' THEN 'N/A'
        WHEN dfs.MinDataSizeMB = dfs.MaxDataSizeMB THEN 'Y'
        ELSE 'N'
    END                                                         AS EqualDataFileSizes,
    -- Equal growth settings flag (data files only)
    CASE
        WHEN fi.FileTypeDesc <> 'ROWS' THEN 'N/A'
        WHEN dfs.MinGrowth = dfs.MaxGrowth
         AND dfs.MinPctGrowth = dfs.MaxPctGrowth THEN 'Y'
        ELSE 'N'
    END                                                         AS EqualGrowthSettings,
    -- Flag files smaller than half the average of other data files
    CASE
        WHEN fi.FileTypeDesc <> 'ROWS' THEN 'N/A'
        WHEN dfs.DataFileCount <= 1 THEN 'N/A'
        WHEN fi.SizeMB < (dfs.AvgDataSizeMB / 2.0) THEN 'Y'
        ELSE 'N'
    END                                                         AS UndersizedFile,
    -- Standing advisory
    'Verify files are pre-sized before workload peaks'          AS PreSizingNote
FROM FileInfo fi
CROSS JOIN DataFileStats dfs
CROSS JOIN LogFiles lf
ORDER BY fi.FileTypeDesc, fi.file_id;

GO



-- ── Part 2: Current TempDB free space from dm_db_file_space_usage ─────────────
SELECT
    database_id,
    CAST(SUM(unallocated_extent_page_count)          * 8.0 / 1024 AS DECIMAL(18,2)) AS FreeSpaceMB,
    CAST(SUM(user_object_reserved_page_count)        * 8.0 / 1024 AS DECIMAL(18,2)) AS UserObjectMB,
    CAST(SUM(internal_object_reserved_page_count)    * 8.0 / 1024 AS DECIMAL(18,2)) AS InternalObjectMB,
    CAST(SUM(version_store_reserved_page_count)      * 8.0 / 1024 AS DECIMAL(18,2)) AS VersionStoreMB,
    CAST(SUM(mixed_extent_page_count)                * 8.0 / 1024 AS DECIMAL(18,2)) AS MixedExtentMB,
    CAST((
          SUM(unallocated_extent_page_count)
        + SUM(user_object_reserved_page_count)
        + SUM(internal_object_reserved_page_count)
        + SUM(version_store_reserved_page_count)
    ) * 8.0 / 1024 AS DECIMAL(18,2))                                                AS TotalAllocatedMB
FROM tempdb.sys.dm_db_file_space_usage
WHERE database_id = 2
GROUP BY database_id;
