-- ============================================================
-- Health Check: Ch 13 Backup and Recovery — 13.1 Backup Coverage
-- Checklist ref: Section 13.1
-- Min SQL version: 2016 (130)
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- Latest full, differential, and log backup per database,
-- joined to sys.databases to flag databases with no backup at all,
-- and FULL-recovery databases that have no log backup in the past 24 hours.

;WITH LatestFull AS (
    SELECT
        bs.database_name,
        MAX(bs.backup_finish_date)                          AS LastFullFinish
    FROM msdb.dbo.backupset bs
    WHERE bs.type = 'D'
    GROUP BY bs.database_name
),
FullDetail AS (
    SELECT
        bs.database_name,
        bs.backup_finish_date,
        bs.backup_start_date,
        CAST(bs.backup_size        / 1048576.0 AS DECIMAL(18,2)) AS SizeMB,
        CAST(bs.compressed_backup_size / 1048576.0 AS DECIMAL(18,2)) AS CompressedMB,
        DATEDIFF(SECOND, bs.backup_start_date, bs.backup_finish_date) AS DurationSec,
        bs.is_copy_only,
        bs.is_password_protected,
        bs.is_snapshot,
        bs.has_backup_checksums,
        -- is_compressed removed in SQL Server 2025; derive from compressed_backup_size
        CASE WHEN bs.compressed_backup_size > 0
              AND bs.compressed_backup_size < bs.backup_size
             THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS is_compressed,
        -- software_name removed in SQL Server 2025; reconstruct from version columns
        'SQL Server ' + CAST(bs.software_major_version AS VARCHAR(5))
            + '.' + CAST(bs.software_minor_version AS VARCHAR(5)) AS software_name,
        bmf.physical_device_name
    FROM msdb.dbo.backupset bs
    INNER JOIN LatestFull lf
        ON  bs.database_name    = lf.database_name
        AND bs.backup_finish_date = lf.LastFullFinish
        AND bs.type             = 'D'
    LEFT JOIN msdb.dbo.backupmediafamily bmf
        ON  bmf.media_set_id    = bs.media_set_id
),
LatestDiff AS (
    SELECT
        bs.database_name,
        MAX(bs.backup_finish_date)                          AS LastDiffFinish
    FROM msdb.dbo.backupset bs
    WHERE bs.type = 'I'
    GROUP BY bs.database_name
),
DiffDetail AS (
    SELECT
        bs.database_name,
        bs.backup_finish_date,
        CAST(bs.backup_size / 1048576.0 AS DECIMAL(18,2))  AS SizeMB
    FROM msdb.dbo.backupset bs
    INNER JOIN LatestDiff ld
        ON  bs.database_name    = ld.database_name
        AND bs.backup_finish_date = ld.LastDiffFinish
        AND bs.type             = 'I'
),
LatestLog AS (
    SELECT
        bs.database_name,
        MAX(bs.backup_finish_date)                          AS LastLogFinish
    FROM msdb.dbo.backupset bs
    WHERE bs.type = 'L'
    GROUP BY bs.database_name
),
LogDetail AS (
    SELECT
        bs.database_name,
        bs.backup_finish_date,
        CAST(bs.backup_size / 1048576.0 AS DECIMAL(18,2))  AS SizeMB
    FROM msdb.dbo.backupset bs
    INNER JOIN LatestLog ll
        ON  bs.database_name    = ll.database_name
        AND bs.backup_finish_date = ll.LastLogFinish
        AND bs.type             = 'L'
)
SELECT
    d.name                                                  AS [DatabaseName],
    d.recovery_model_desc                                   AS [RecoveryModel],
    -- Full backup
    fd.backup_finish_date                                   AS [LastFullBackup],
    fd.SizeMB                                               AS [LastFullSizeMB],
    fd.CompressedMB                                         AS [LastFullCompressedMB],
    fd.DurationSec                                          AS [LastFullDurationSec],
    fd.physical_device_name                                 AS [LastFullLocation],
    fd.software_name                                        AS [LastFullSoftware],
    fd.has_backup_checksums                                 AS [LastFullChecksumFlag],
    fd.is_copy_only                                         AS [LastFullIsCopyOnly],
    fd.is_password_protected                                AS [LastFullIsPasswordProtected],
    fd.is_snapshot                                          AS [LastFullIsSnapshot],
    fd.is_compressed                                        AS [LastFullIsCompressed],
    -- Differential backup
    dd.backup_finish_date                                   AS [LastDiffBackup],
    dd.SizeMB                                               AS [LastDiffSizeMB],
    -- Log backup
    ld.backup_finish_date                                   AS [LastLogBackup],
    ld.SizeMB                                               AS [LastLogSizeMB],
    -- Coverage flags
    CASE WHEN fd.database_name IS NULL THEN 1 ELSE 0 END   AS [HasNoBackup],
    CASE
        WHEN d.recovery_model_desc = 'FULL'
         AND (ld.backup_finish_date IS NULL
              OR ld.backup_finish_date < DATEADD(HOUR, -24, GETDATE()))
        THEN 1
        ELSE 0
    END                                                     AS [FullRecoveryNoRecentLog]
FROM sys.databases d
LEFT JOIN FullDetail  fd ON fd.database_name = d.name
LEFT JOIN DiffDetail  dd ON dd.database_name = d.name
LEFT JOIN LogDetail   ld ON ld.database_name = d.name
WHERE d.state_desc = 'ONLINE'
  AND d.database_id > 4           -- exclude system databases from main view
ORDER BY
    [HasNoBackup] DESC,
    [FullRecoveryNoRecentLog] DESC,
    d.name;
