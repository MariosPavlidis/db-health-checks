-- ============================================================
-- Health Check: Ch 13 Backup and Recovery — 13.3 RPO Compliance (Log Backup Frequency)
-- Checklist ref: Section 13.3
-- Min SQL version: 2016 (130)
-- Note: Estimated backup-based RPO only.
--       Actual RPO requires restore validation.
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- Analyze log backup frequency over the past 90 days using LAG() to
-- compute intervals between consecutive log backups per database.
-- Flags databases where the maximum gap exceeds 60 minutes (FULL recovery).
-- Also flags databases currently exposed (minutes since last log backup
-- exceeds the average interval for that database).

;WITH LogBackups AS (
    SELECT
        bs.database_name,
        bs.backup_finish_date,
        -- Gap in minutes from the previous log backup for this database
        DATEDIFF(
            MINUTE,
            LAG(bs.backup_finish_date) OVER (
                PARTITION BY bs.database_name
                ORDER BY bs.backup_finish_date
            ),
            bs.backup_finish_date
        )                                                   AS GapMinutes
    FROM msdb.dbo.backupset bs
    WHERE bs.type               = 'L'
      AND bs.backup_finish_date >= DATEADD(DAY, -90, GETDATE())
),
LogStats AS (
    SELECT
        lb.database_name,
        COUNT(*)                                            AS BackupCount,
        AVG(CAST(lb.GapMinutes AS FLOAT))                  AS AvgIntervalMinutes,
        MAX(lb.GapMinutes)                                  AS MaxGapMinutes,
        MAX(lb.backup_finish_date)                          AS LastLogBackup
    FROM LogBackups lb
    WHERE lb.GapMinutes IS NOT NULL   -- exclude first row per DB (no prior log)
    GROUP BY lb.database_name
)
SELECT
    d.name                                                  AS [DatabaseName],
    d.recovery_model_desc                                   AS [RecoveryModel],
    ls.BackupCount                                          AS [LogBackupCount90d],
    CAST(ls.AvgIntervalMinutes AS DECIMAL(10,1))            AS [AvgIntervalMinutes],
    ls.MaxGapMinutes                                        AS [MaxGapMinutes],
    ls.LastLogBackup                                        AS [LastLogBackup],
    DATEDIFF(MINUTE, ls.LastLogBackup, GETDATE())           AS [MinutesSinceLastLog],
    -- missed_windows_flag: max gap > 60 min for FULL-recovery databases
    CASE
        WHEN d.recovery_model_desc = 'FULL'
         AND ls.MaxGapMinutes      > 60
        THEN 1
        ELSE 0
    END                                                     AS [MissedWindowsFlag],
    -- currently_exposed: minutes since last log > avg interval (or no log backup)
    CASE
        WHEN d.recovery_model_desc = 'FULL'
         AND (ls.LastLogBackup IS NULL
              OR DATEDIFF(MINUTE, ls.LastLogBackup, GETDATE()) > ISNULL(ls.AvgIntervalMinutes, 0))
        THEN 1
        ELSE 0
    END                                                     AS [CurrentlyExposed],
    -- Databases in FULL recovery with no log backups at all in the window
    CASE
        WHEN d.recovery_model_desc = 'FULL'
         AND ls.database_name      IS NULL
        THEN 1
        ELSE 0
    END                                                     AS [NoLogBackupsInWindow]
FROM sys.databases d
LEFT JOIN LogStats ls ON ls.database_name = d.name
WHERE d.state_desc     = 'ONLINE'
  AND d.database_id    > 4          -- exclude system databases
ORDER BY
    [CurrentlyExposed] DESC,
    [MissedWindowsFlag] DESC,
    [MaxGapMinutes] DESC,
    d.name;
