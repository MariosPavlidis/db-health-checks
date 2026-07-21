-- ============================================================
-- Health Check: Ch 07 Transaction Log — 7.4 Log Backup Behavior
-- Checklist ref: Section 7.4
-- Min SQL version: 2016 (130)
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- ── Part 1: Log backup summary per database — last 30 days ───────────────────
-- Uses LAG() to calculate the gap between consecutive log backups.
-- Flags: gaps > 60 minutes for FULL-recovery databases.

;WITH LogBackups AS (
    SELECT
        bs.database_name,
        bs.backup_start_date,
        bs.backup_finish_date,
        bs.backup_size,
        bs.compressed_backup_size,
        -- Gap in minutes between this backup and the previous one for the same database
        DATEDIFF(MINUTE,
            LAG(bs.backup_finish_date) OVER (
                PARTITION BY bs.database_name
                ORDER BY bs.backup_finish_date
            ),
            bs.backup_start_date
        )                                           AS GapFromPreviousMin,
        ROW_NUMBER() OVER (
            PARTITION BY bs.database_name
            ORDER BY bs.backup_finish_date DESC
        )                                           AS RowDesc
    FROM msdb.dbo.backupset bs
    WHERE bs.type = 'L'
      AND bs.backup_finish_date >= DATEADD(DAY, -30, GETDATE())
),
PerDbStats AS (
    SELECT
        lb.database_name,
        COUNT(*)                                    AS LogBackupCount,
        MAX(CASE WHEN lb.RowDesc = 1 THEN lb.backup_finish_date END)
                                                    AS LastLogBackup,
        CAST(AVG(CAST(lb.GapFromPreviousMin AS FLOAT)) AS DECIMAL(18,1))
                                                    AS AvgLogBackupIntervalMin,
        MAX(lb.GapFromPreviousMin)                  AS MaxLogBackupGapMin,
        CAST(AVG(lb.backup_size          / 1048576.0) AS DECIMAL(18,2))
                                                    AS AvgLogBackupSizeMB,
        CAST(AVG(lb.compressed_backup_size / 1048576.0) AS DECIMAL(18,2))
                                                    AS AvgCompressedSizeMB,
        -- Compression: compressed_backup_size < backup_size indicates compressed backup
        MAX(CASE WHEN lb.compressed_backup_size < lb.backup_size THEN 1 ELSE 0 END)
                                                    AS LogBackupCompressionEnabled,
        -- Count of gaps > 60 minutes within the 30-day window
        SUM(CASE WHEN lb.GapFromPreviousMin > 60 THEN 1 ELSE 0 END)
                                                    AS GapsOver60Min
    FROM LogBackups lb
    GROUP BY lb.database_name
)
SELECT
    d.name                                          AS DatabaseName,
    d.recovery_model_desc                           AS RecoveryModel,
    COALESCE(pds.LastLogBackup, NULL)               AS LastLogBackup,
    COALESCE(pds.LogBackupCount, 0)                 AS LogBackupCount30Days,
    pds.AvgLogBackupIntervalMin,
    pds.MaxLogBackupGapMin,
    pds.AvgLogBackupSizeMB,
    pds.AvgCompressedSizeMB,
    pds.LogBackupCompressionEnabled,
    pds.GapsOver60Min                               AS GapsOver60MinIn30Days,
    -- Flag for FULL-recovery databases with concerning gaps
    CASE
        WHEN d.recovery_model_desc IN ('FULL', 'BULK_LOGGED')
         AND pds.GapsOver60Min > 0
        THEN 'Y'
        ELSE 'N'
    END                                             AS HasMissedLogBackupWindows,
    CASE
        WHEN d.recovery_model_desc IN ('FULL', 'BULK_LOGGED')
         AND pds.LastLogBackup IS NULL
        THEN 'NO_LOG_BACKUPS_30DAYS'
        WHEN d.recovery_model_desc IN ('FULL', 'BULK_LOGGED')
         AND pds.MaxLogBackupGapMin > 1440
        THEN 'GAP_EXCEEDS_24H'
        WHEN d.recovery_model_desc IN ('FULL', 'BULK_LOGGED')
         AND pds.MaxLogBackupGapMin > 60
        THEN 'GAP_EXCEEDS_1H'
        ELSE 'OK'
    END                                             AS LogBackupRiskLevel
FROM sys.databases                                  d
LEFT JOIN PerDbStats                                pds ON pds.database_name = d.name
WHERE d.state_desc = 'ONLINE'
  AND d.database_id > 4       -- exclude system databases from main view
ORDER BY
    CASE
        WHEN d.recovery_model_desc IN ('FULL','BULK_LOGGED') AND pds.LastLogBackup IS NULL THEN 1
        WHEN pds.MaxLogBackupGapMin > 1440 THEN 2
        WHEN pds.MaxLogBackupGapMin > 60   THEN 3
        ELSE 4
    END,
    d.name;

GO

-- ── Part 2: Detailed backup gap list — individual gaps > 60 min (last 30 days) ─
;WITH LogBackups AS (
    SELECT
        bs.database_name,
        bs.backup_finish_date                       AS ThisBackup,
        LAG(bs.backup_finish_date) OVER (
            PARTITION BY bs.database_name
            ORDER BY bs.backup_finish_date
        )                                           AS PreviousBackup,
        DATEDIFF(MINUTE,
            LAG(bs.backup_finish_date) OVER (
                PARTITION BY bs.database_name
                ORDER BY bs.backup_finish_date
            ),
            bs.backup_start_date
        )                                           AS GapMinutes
    FROM msdb.dbo.backupset bs
    WHERE bs.type = 'L'
      AND bs.backup_finish_date >= DATEADD(DAY, -30, GETDATE())
)
SELECT
    lb.database_name                                AS DatabaseName,
    d.recovery_model_desc                           AS RecoveryModel,
    lb.PreviousBackup,
    lb.ThisBackup,
    lb.GapMinutes,
    CAST(lb.GapMinutes / 60.0 AS DECIMAL(6,1))     AS GapHours
FROM LogBackups                                     lb
JOIN sys.databases                                  d   ON d.name = lb.database_name
WHERE lb.GapMinutes > 60
  AND d.state_desc = 'ONLINE'
ORDER BY lb.GapMinutes DESC, lb.database_name;

GO

-- ── Part 3: Damaged log backup records ────────────────────────────────────────
-- Backup sets flagged as damaged in msdb history.
SELECT
    bs.database_name                                AS DatabaseName,
    bs.backup_start_date,
    bs.backup_finish_date,
    bs.type                                         AS BackupType,
    bs.is_damaged,
    bs.is_password_protected,
    bs.has_incomplete_metadata,
    bmf.physical_device_name                        AS BackupDevice
FROM msdb.dbo.backupset                             bs
LEFT JOIN msdb.dbo.backupmediafamily                bmf ON bmf.media_set_id = bs.media_set_id
WHERE bs.type        = 'L'
  AND bs.is_damaged  = 1
  AND bs.backup_finish_date >= DATEADD(DAY, -30, GETDATE())
ORDER BY bs.backup_finish_date DESC;
