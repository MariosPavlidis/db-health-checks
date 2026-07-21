-- ============================================================
-- Health Check: Ch 07 Transaction Log — 7.1 Log File Configuration
-- Checklist ref: Section 7.1
-- Min SQL version: 2016 (130)
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- ── Part 1: Log file configuration per database ───────────────────────────────
-- Flags:
--   OversizedLog          : log > 50 GB (indicative — adjust threshold for workload)
--   UndersizedLog         : log < 256 MB for non-Simple recovery databases
--   LogSharingStorageWithData : log drive/path matches a data file path for the same DB
--   NoRecentLogBackup     : FULL recovery database with no log backup in the past 24 hours

;WITH LogFiles AS (
    SELECT
        mf.database_id,
        mf.name                                     AS LogicalName,
        mf.physical_name                            AS LogFilePath,
        CAST(mf.size * 8.0 / 1024 AS DECIMAL(18,2))
                                                    AS LogSizeMB,
        CASE mf.max_size
            WHEN -1 THEN -1
            WHEN  0 THEN  0
            ELSE CAST(mf.max_size * 8.0 / 1024 AS DECIMAL(18,2))
        END                                         AS LogMaxSizeMB,
        CASE
            WHEN mf.is_percent_growth = 1
                THEN CAST(mf.growth AS VARCHAR(10)) + '%'
            ELSE CAST(CAST(mf.growth * 8.0 / 1024 AS DECIMAL(18,2)) AS VARCHAR(20)) + ' MB'
        END                                         AS LogGrowthSetting,
        mf.is_percent_growth                        AS IsPercentGrowth,
        -- Extract drive/volume prefix for storage overlap detection
        UPPER(LEFT(mf.physical_name,
               CHARINDEX('\', mf.physical_name + '\', 3) - 1))
                                                    AS LogDrive
    FROM sys.master_files mf
    WHERE mf.type = 1   -- log files only
),
DataDrives AS (
    SELECT
        mf.database_id,
        UPPER(LEFT(mf.physical_name,
               CHARINDEX('\', mf.physical_name + '\', 3) - 1))
                                                    AS DataDrive
    FROM sys.master_files mf
    WHERE mf.type = 0   -- data files
    GROUP BY mf.database_id,
             UPPER(LEFT(mf.physical_name,
                    CHARINDEX('\', mf.physical_name + '\', 3) - 1))
),
LastLogBackup AS (
    SELECT
        database_name,
        MAX(backup_finish_date)                     AS LastLogBackupDate,
        CAST(MAX(backup_size) / 1048576.0 AS DECIMAL(18,2))
                                                    AS LastLogBackupSizeMB
    FROM msdb.dbo.backupset
    WHERE type = 'L'
    GROUP BY database_name
),
-- dm_db_log_space_usage requires the context of each database; accessed via sys here
-- as a cross-instance aggregate is not feasible without dynamic SQL at this scope.
-- Use dm_db_log_info to count VLFs per database via aggregate below.
VLFCounts AS (
    -- Aggregate VLF counts from dm_db_log_info for online databases.
    -- NOTE: SQL 2016+ only.  Results are collected for all databases at collection time.
    SELECT
        database_id,
        COUNT(*)                                    AS TotalVLFs,
        SUM(CASE WHEN vlf_active = 1 THEN 1 ELSE 0 END)
                                                    AS ActiveVLFs
    FROM sys.dm_db_log_info(NULL)
    GROUP BY database_id
)
SELECT
    d.name                                          AS DatabaseName,
    d.recovery_model_desc                           AS RecoveryModel,
    d.log_reuse_wait_desc                           AS LogReuseWaitDesc,
    lf.LogicalName,
    lf.LogFilePath,
    lf.LogSizeMB,
    lf.LogMaxSizeMB,
    lf.LogGrowthSetting,
    lf.IsPercentGrowth,
    d.state_desc                                    AS DatabaseState,
    -- VLF summary (from dm_db_log_info aggregated above)
    vlf.TotalVLFs,
    vlf.ActiveVLFs,
    -- Log backup info
    llb.LastLogBackupDate,
    llb.LastLogBackupSizeMB,
    -- Flags
    CASE WHEN lf.LogSizeMB > 51200 THEN 'Y' ELSE 'N' END
                                                    AS OversizedLog,
    CASE
        WHEN d.recovery_model_desc <> 'SIMPLE'
         AND lf.LogSizeMB < 256 THEN 'Y'
        ELSE 'N'
    END                                             AS UndersizedLog,
    CASE
        WHEN EXISTS (
            SELECT 1 FROM DataDrives dd
            WHERE dd.database_id = d.database_id
              AND dd.DataDrive    = lf.LogDrive
        ) THEN 'Y'
        ELSE 'N'
    END                                             AS LogSharingStorageWithData,
    CASE
        WHEN d.recovery_model_desc = 'FULL'
         AND (llb.LastLogBackupDate IS NULL
              OR llb.LastLogBackupDate < DATEADD(HOUR, -24, GETDATE()))
        THEN 'Y'
        ELSE 'N'
    END                                             AS NoRecentLogBackup
FROM sys.databases                                  d
JOIN LogFiles                                       lf  ON lf.database_id = d.database_id
LEFT JOIN VLFCounts                                 vlf ON vlf.database_id = d.database_id
LEFT JOIN LastLogBackup                             llb ON llb.database_name = d.name
WHERE d.state_desc = 'ONLINE'
ORDER BY
    NoRecentLogBackup DESC,
    OversizedLog      DESC,
    d.name;
