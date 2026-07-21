-- ============================================================
-- Health Check: Ch 22 Maintenance and Operational Governance — 22.1 Maintenance Job Coverage
-- Checklist ref: Section 22.1
-- Min SQL version: 2016 (130)
-- ============================================================
-- Identifies SQL Agent job steps that perform key maintenance operations:
-- full/log backups, DBCC CHECKDB, UPDATE STATISTICS, index rebuild/reorganize,
-- and backup history cleanup. Categorises each step so coverage gaps can be
-- identified by comparing against sys.databases separately.
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- Jobs by maintenance category
SELECT
    j.name                                          AS JobName,
    j.enabled                                       AS JobEnabled,
    s.step_id                                       AS StepId,
    s.step_name                                     AS StepName,
    s.command                                       AS Command,
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
    j.date_created                                  AS DateCreated,
    j.date_modified                                 AS DateModified,
    SUSER_SNAME(j.owner_sid)                        AS Owner
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobsteps s
    ON s.job_id = j.job_id
WHERE s.command LIKE '%BACKUP%'
   OR s.command LIKE '%CHECKDB%'
   OR s.command LIKE '%STATISTICS%'
   OR s.command LIKE '%REBUILD%'
   OR s.command LIKE '%REORGANIZE%'
   OR s.command LIKE '%sp_delete%history%'
   OR s.command LIKE '%CleanupHistory%'
ORDER BY MaintenanceCategory, j.name;
