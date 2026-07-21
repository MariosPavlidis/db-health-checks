-- ============================================================
-- Health Check: Ch 22 Maintenance and Operational Governance — 22.2 Maintenance Effectiveness
-- Checklist ref: Section 22.2
-- Min SQL version: 2016 (130)
-- ============================================================
-- Analyses SQL Agent job history for maintenance-category jobs over the
-- last 90 days. Flags jobs whose most recent run was a failure and jobs
-- that appear to report success but processed zero rows/databases.
-- Also reports current msdb data file size as a maintenance health indicator.
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- Maintenance job run history (last 90 days)
;WITH LastJobRun AS (
    SELECT job_id, MAX(run_date) AS MaxRunDate
    FROM msdb.dbo.sysjobhistory
    WHERE step_id = 0
    GROUP BY job_id
)
SELECT
    j.name                                          AS JobName,
    j.enabled                                       AS JobEnabled,
    CASE
        WHEN s.command LIKE '%BACKUP DATABASE%'                             THEN 'FULL_BACKUP'
        WHEN s.command LIKE '%BACKUP LOG%'                                  THEN 'LOG_BACKUP'
        WHEN s.command LIKE '%DBCC CHECKDB%'
          OR s.command LIKE '%DBCC CHECKFILEGROUP%'                         THEN 'INTEGRITY_CHECK'
        WHEN s.command LIKE '%UPDATE STATISTICS%'                           THEN 'STATISTICS'
        WHEN s.command LIKE '%REBUILD%'
          OR s.command LIKE '%REORGANIZE%'                                  THEN 'INDEX_MAINTENANCE'
        WHEN s.command LIKE '%DELETE%msdb%backupset%'
          OR s.command LIKE '%sp_delete_backuphistory%'                     THEN 'HISTORY_CLEANUP'
        ELSE 'OTHER'
    END                                             AS MaintenanceCategory,
    COUNT(*)                                        AS TotalRuns,
    SUM(CASE WHEN jh.run_status = 1 THEN 1 ELSE 0 END)  AS SuccessCount,
    SUM(CASE WHEN jh.run_status <> 1 THEN 1 ELSE 0 END) AS FailureCount,
    -- Most recent run details
    MAX(CAST(
        CONVERT(VARCHAR(8), jh.run_date)  + ' ' +
        STUFF(STUFF(RIGHT('000000' + CAST(jh.run_time AS VARCHAR(6)),6),5,0,':'),3,0,':')
        AS DATETIME))                               AS LastRunDateTime,
    -- Last run status (0=Failed,1=Succeeded,2=Retry,3=Cancelled,5=Unknown)
    MAX(CASE WHEN jh.run_date = lr.MaxRunDate
             THEN jh.run_status ELSE NULL END)      AS LastRunStatus,
    -- Flag jobs with any recent failure
    CASE WHEN SUM(CASE WHEN jh.run_status <> 1 THEN 1 ELSE 0 END) > 0
         THEN 'HAS_FAILURES'
         ELSE ''
    END                                             AS FailureFlag,
    -- Flag jobs that succeeded but step output mentions processing 0 databases
    CASE WHEN MAX(CASE WHEN jh.run_status = 1
                            AND jh.message LIKE '%Processed 0%' THEN 1 ELSE 0 END) = 1
         THEN 'SUCCESS_ZERO_PROCESSED'
         ELSE ''
    END                                             AS ZeroProcessedFlag
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobsteps s
    ON s.job_id = j.job_id
JOIN msdb.dbo.sysjobhistory jh
    ON jh.job_id = j.job_id
   AND jh.step_id = s.step_id
LEFT JOIN LastJobRun lr
    ON lr.job_id = j.job_id
WHERE (
    s.command LIKE '%BACKUP%'
    OR s.command LIKE '%CHECKDB%'
    OR s.command LIKE '%STATISTICS%'
    OR s.command LIKE '%REBUILD%'
    OR s.command LIKE '%REORGANIZE%'
    OR s.command LIKE '%sp_delete%history%'
    OR s.command LIKE '%CleanupHistory%'
)
AND msdb.dbo.agent_datetime(jh.run_date, jh.run_time) >= DATEADD(DAY, -90, GETDATE())
GROUP BY j.name, j.enabled, s.command
ORDER BY FailureFlag DESC, j.name;

GO

-- msdb size check
SELECT
    SUM(mf.size) * 8 / 1024                        AS MsdbSizeMB
FROM sys.master_files mf
JOIN sys.databases d
    ON d.database_id = mf.database_id
WHERE d.name = 'msdb';
