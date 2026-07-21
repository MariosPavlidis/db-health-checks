-- ============================================================
-- Health Check: Ch 19 Availability Groups — 19.5 AG Backup Configuration
-- Checklist ref: Section 19.5
-- Min SQL version: 2016 (130)
-- ============================================================
-- Displays backup preference and per-replica backup priority alongside
-- current role. Provides an interpreted note describing whether each
-- replica is an eligible backup target under the current preference.
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

IF CAST(SERVERPROPERTY('IsHadrEnabled') AS INT) = 0
BEGIN
    SELECT 'HADR not enabled' AS Note; RETURN;
END
GO

SELECT
    ag.name                                         AS AGName,
    ag.automated_backup_preference_desc             AS BackupPreference,
    ar.replica_server_name                          AS ReplicaServer,
    ar.backup_priority                              AS BackupPriority,
    ars.role_desc                                   AS CurrentRole,
    -- Expected backup target based on preference
    CASE ag.automated_backup_preference
        WHEN 0 THEN 'No preference — any replica'
        WHEN 1 THEN 'Secondary preferred — this replica ' +
                     CASE WHEN ars.role_desc = 'SECONDARY' THEN 'is eligible'
                          ELSE 'is NOT preferred' END
        WHEN 2 THEN 'Secondary only — this replica ' +
                     CASE WHEN ars.role_desc = 'SECONDARY' THEN 'is eligible'
                          ELSE 'is excluded' END
        WHEN 3 THEN 'Primary only — this replica ' +
                     CASE WHEN ars.role_desc = 'PRIMARY'   THEN 'is the target'
                          ELSE 'is excluded' END
    END                                             AS BackupTargetNote
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar
    ON ar.group_id = ag.group_id
JOIN sys.dm_hadr_availability_replica_states ars
    ON ars.replica_id = ar.replica_id
ORDER BY ag.name, ar.backup_priority DESC;
