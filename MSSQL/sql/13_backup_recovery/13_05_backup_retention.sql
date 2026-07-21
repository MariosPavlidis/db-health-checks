-- ============================================================
-- Health Check: Ch 13 Backup and Recovery — 13.5 Backup Retention and Cleanup
-- Checklist ref: Section 13.5
-- Min SQL version: 2016 (130)
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- ── Section A: Backup record counts per database, type, and age bucket ─────────

SELECT
    bs.database_name                                        AS [DatabaseName],
    CASE bs.type
        WHEN 'D' THEN 'Full'
        WHEN 'I' THEN 'Differential'
        WHEN 'L' THEN 'Log'
        WHEN 'F' THEN 'File/Filegroup'
        WHEN 'G' THEN 'Differential File'
        WHEN 'P' THEN 'Partial'
        WHEN 'Q' THEN 'Differential Partial'
        ELSE bs.type
    END                                                     AS [BackupType],
    bs.type                                                 AS [BackupTypeCode],
    SUM(CASE
        WHEN bs.backup_finish_date >= DATEADD(DAY,  -7, GETDATE()) THEN 1 ELSE 0
    END)                                                    AS [Last7dCount],
    SUM(CASE
        WHEN bs.backup_finish_date <  DATEADD(DAY,  -7, GETDATE())
         AND bs.backup_finish_date >= DATEADD(DAY, -30, GETDATE()) THEN 1 ELSE 0
    END)                                                    AS [Day8to30Count],
    SUM(CASE
        WHEN bs.backup_finish_date <  DATEADD(DAY, -30, GETDATE())
         AND bs.backup_finish_date >= DATEADD(DAY, -90, GETDATE()) THEN 1 ELSE 0
    END)                                                    AS [Day31to90Count],
    SUM(CASE
        WHEN bs.backup_finish_date <  DATEADD(DAY, -90, GETDATE()) THEN 1 ELSE 0
    END)                                                    AS [Day91PlusCount],
    COUNT(*)                                                AS [TotalCount],
    -- Flag databases accumulating many backups without cleanup in the last 7 days
    CASE
        WHEN SUM(CASE
            WHEN bs.backup_finish_date >= DATEADD(DAY, -7, GETDATE()) THEN 1 ELSE 0
        END) > 100
        THEN 1
        ELSE 0
    END                                                     AS [ExcessiveBackupsLast7dFlag]
FROM msdb.dbo.backupset bs
GROUP BY
    bs.database_name,
    bs.type
ORDER BY
    [ExcessiveBackupsLast7dFlag] DESC,
    bs.database_name,
    bs.type;

GO

-- ── Section B: Backup storage locations (physical device paths) ─────────────────

SELECT DISTINCT
    bs.database_name                                        AS [DatabaseName],
    CASE bs.type
        WHEN 'D' THEN 'Full'
        WHEN 'I' THEN 'Differential'
        WHEN 'L' THEN 'Log'
        ELSE bs.type
    END                                                     AS [BackupType],
    bmf.device_type                                         AS [DeviceType],
    bmf.physical_device_name                                AS [PhysicalDeviceName],
    -- Derive path root for grouping (everything up to and including the last backslash or slash)
    CASE
        WHEN bmf.physical_device_name LIKE '%\%'
        THEN LEFT(bmf.physical_device_name,
                  LEN(bmf.physical_device_name)
                  - CHARINDEX('\', REVERSE(bmf.physical_device_name)) + 1)
        WHEN bmf.physical_device_name LIKE '%/%'
        THEN LEFT(bmf.physical_device_name,
                  LEN(bmf.physical_device_name)
                  - CHARINDEX('/', REVERSE(bmf.physical_device_name)) + 1)
        ELSE bmf.physical_device_name
    END                                                     AS [LocationPath]
FROM msdb.dbo.backupset bs
INNER JOIN msdb.dbo.backupmediafamily bmf
    ON bmf.media_set_id = bs.media_set_id
WHERE bs.backup_finish_date >= DATEADD(DAY, -90, GETDATE())
ORDER BY
    bs.database_name,
    [BackupType],
    bmf.physical_device_name;

GO

-- ── Section C: SQL Agent jobs containing BACKUP commands ───────────────────────

SELECT
    j.name                                                  AS [JobName],
    j.enabled                                               AS [JobEnabled],
    j.description                                           AS [JobDescription],
    js.step_id                                              AS [StepId],
    js.step_name                                            AS [StepName],
    js.subsystem                                            AS [Subsystem],
    -- Truncate command to first 500 chars for readability
    LEFT(js.command, 500)                                   AS [CommandSnippet],
    j.date_created                                          AS [JobCreated],
    j.date_modified                                         AS [JobModified]
FROM msdb.dbo.sysjobs j
INNER JOIN msdb.dbo.sysjobsteps js
    ON js.job_id = j.job_id
WHERE js.command LIKE '%BACKUP%'
ORDER BY
    j.name,
    js.step_id;

GO

-- ── Section D: Failed backup-related job step history (last 90 days) ───────────

SELECT
    j.name                                                  AS [JobName],
    js.step_name                                            AS [StepName],
    js.subsystem                                            AS [Subsystem],
    -- jh.run_date is YYYYMMDD int; jh.run_time is HHMMSS int
    CONVERT(DATETIME,
        STUFF(STUFF(CAST(jh.run_date AS VARCHAR(8)), 5, 0, '-'), 8, 0, '-')
        + ' '
        + STUFF(STUFF(RIGHT('000000' + CAST(jh.run_time AS VARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':')
    )                                                       AS [RunDateTime],
    jh.run_status                                           AS [RunStatus],
    -- 0=Failed,1=Succeeded,2=Retry,3=Cancelled,4=In Progress
    CASE jh.run_status
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Cancelled'
        WHEN 4 THEN 'In Progress'
        ELSE CAST(jh.run_status AS VARCHAR(5))
    END                                                     AS [RunStatusDesc],
    jh.run_duration                                         AS [RunDuration],
    LEFT(jh.message, 500)                                   AS [MessageSnippet],
    j.enabled                                               AS [JobEnabled]
FROM msdb.dbo.sysjobs j
INNER JOIN msdb.dbo.sysjobsteps js
    ON js.job_id = j.job_id
INNER JOIN msdb.dbo.sysjobhistory jh
    ON  jh.job_id   = j.job_id
    AND jh.step_id  = js.step_id
WHERE js.command LIKE '%BACKUP%'
  AND jh.run_status <> 1      -- exclude successful runs
  AND CONVERT(DATETIME,
        STUFF(STUFF(CAST(jh.run_date AS VARCHAR(8)), 5, 0, '-'), 8, 0, '-')
        + ' '
        + STUFF(STUFF(RIGHT('000000' + CAST(jh.run_time AS VARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':')
    ) >= DATEADD(DAY, -90, GETDATE())
ORDER BY
    [RunDateTime] DESC,
    j.name;

GO

-- ── Section E: Average backup throughput (last 10 full backups per database) ───

;WITH RankedFullBackups AS (
    SELECT
        bs.database_name,
        bs.backup_start_date,
        bs.backup_finish_date,
        bs.backup_size,
        DATEDIFF(SECOND, bs.backup_start_date, bs.backup_finish_date) AS DurationSec,
        ROW_NUMBER() OVER (
            PARTITION BY bs.database_name
            ORDER BY bs.backup_finish_date DESC
        )                                                   AS rn
    FROM msdb.dbo.backupset bs
    WHERE bs.type = 'D'
),
Last10Full AS (
    SELECT *
    FROM RankedFullBackups
    WHERE rn <= 10
)
SELECT
    database_name                                           AS [DatabaseName],
    COUNT(*)                                                AS [FullBackupCount],
    CAST(AVG(CAST(backup_size AS FLOAT) / 1048576.0) AS DECIMAL(18,2))
                                                            AS [AvgSizeMB],
    CAST(AVG(CAST(DurationSec AS FLOAT)) AS DECIMAL(10,1)) AS [AvgDurationSec],
    CAST(
        CASE
            WHEN AVG(CAST(DurationSec AS FLOAT)) > 0
            THEN AVG(CAST(backup_size AS FLOAT) / 1048576.0)
                 / AVG(CAST(DurationSec AS FLOAT))
            ELSE NULL
        END
    AS DECIMAL(18,2))                                       AS [AvgThroughputMBPerSec],
    MIN(backup_finish_date)                                 AS [OldestOfLast10],
    MAX(backup_finish_date)                                 AS [MostRecent]
FROM Last10Full
GROUP BY database_name
ORDER BY database_name;
