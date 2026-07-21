-- ============================================================
-- Health Check: Ch 07 Transaction Log — 7.2 VLF Health
-- Checklist ref: Section 7.2
-- Min SQL version: 2016 (130)
-- ============================================================
-- sys.dm_db_log_info is a SQL 2016+ DMF.
-- This script uses a cursor with dynamic SQL to gather VLF counts
-- for every ONLINE database, then flags excessive or fragmented VLF layouts.
-- VLF flags:
--   EXCESSIVE_VLF  : total VLF count > 1000 (high fragmentation, slow recovery)
--   MANY_SMALL_VLF : many VLFs present and smallest VLF < 0.5 MB (autogrowth artifact)
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- Create a temp table to collect results across cursor iterations
IF OBJECT_ID('tempdb..#VLFSummary') IS NOT NULL DROP TABLE #VLFSummary;

CREATE TABLE #VLFSummary (
    DatabaseName    SYSNAME         NOT NULL,
    TotalVLFs       INT             NOT NULL,
    ActiveVLFs      INT             NOT NULL,
    InactiveVLFs    INT             NOT NULL,
    MinVLFSizeMB    DECIMAL(18,4)   NULL,
    MaxVLFSizeMB    DECIMAL(18,4)   NULL,
    AvgVLFSizeMB    DECIMAL(18,4)   NULL,
    TotalLogSizeMB  DECIMAL(18,2)   NULL,
    VLFFlag         NVARCHAR(50)    NOT NULL DEFAULT ''
);

DECLARE @sql NVARCHAR(MAX);
DECLARE @db  SYSNAME;

DECLARE db_cursor CURSOR FAST_FORWARD FOR
    SELECT name
    FROM sys.databases
    WHERE state_desc = 'ONLINE'
    ORDER BY name;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
    INSERT INTO #VLFSummary
        (DatabaseName, TotalVLFs, ActiveVLFs, InactiveVLFs,
         MinVLFSizeMB, MaxVLFSizeMB, AvgVLFSizeMB, TotalLogSizeMB, VLFFlag)
    SELECT
        DB_NAME()                                           AS DatabaseName,
        COUNT(*)                                            AS TotalVLFs,
        SUM(CASE WHEN vlf_active = 1 THEN 1 ELSE 0 END)   AS ActiveVLFs,
        SUM(CASE WHEN vlf_active = 0 THEN 1 ELSE 0 END)   AS InactiveVLFs,
        MIN(CAST(vlf_size_mb AS DECIMAL(18,4)))            AS MinVLFSizeMB,
        MAX(CAST(vlf_size_mb AS DECIMAL(18,4)))            AS MaxVLFSizeMB,
        AVG(CAST(vlf_size_mb AS DECIMAL(18,4)))            AS AvgVLFSizeMB,
        SUM(CAST(vlf_size_mb AS DECIMAL(18,4)))            AS TotalLogSizeMB,
        CASE
            WHEN COUNT(*) > 1000
                THEN ''EXCESSIVE_VLF''
            WHEN MIN(CAST(vlf_size_mb AS DECIMAL(18,4))) < 0.5
             AND COUNT(*) > 100
                THEN ''MANY_SMALL_VLF''
            ELSE ''''
        END                                                 AS VLFFlag
    FROM sys.dm_db_log_info(NULL);';

    BEGIN TRY
        EXEC sp_executesql @sql;
    END TRY
    BEGIN CATCH
        -- Insert a placeholder row so the database still appears in output
        INSERT INTO #VLFSummary
            (DatabaseName, TotalVLFs, ActiveVLFs, InactiveVLFs, VLFFlag)
        VALUES
            (@db, -1, -1, -1, 'ERROR: ' + ERROR_MESSAGE());
    END CATCH

    FETCH NEXT FROM db_cursor INTO @db;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;

-- Return results ordered by most problematic first
SELECT
    v.DatabaseName,
    v.TotalVLFs,
    v.ActiveVLFs,
    v.InactiveVLFs,
    v.MinVLFSizeMB,
    v.MaxVLFSizeMB,
    v.AvgVLFSizeMB,
    v.TotalLogSizeMB,
    v.VLFFlag,
    -- Advisory text
    CASE v.VLFFlag
        WHEN 'EXCESSIVE_VLF'
            THEN 'Shrink and pre-grow log file with a single large growth to reduce VLF count'
        WHEN 'MANY_SMALL_VLF'
            THEN 'Log has many small VLFs from frequent auto-growth; set fixed growth increment >= 512 MB'
        ELSE ''
    END                                                     AS Recommendation,
    d.recovery_model_desc                                   AS RecoveryModel,
    d.log_reuse_wait_desc                                   AS LogReuseWaitDesc
FROM #VLFSummary                                            v
JOIN sys.databases                                          d
    ON d.name = v.DatabaseName
ORDER BY
    CASE v.VLFFlag
        WHEN 'EXCESSIVE_VLF'  THEN 1
        WHEN 'MANY_SMALL_VLF' THEN 2
        ELSE 3
    END,
    v.TotalVLFs DESC;

DROP TABLE #VLFSummary;
