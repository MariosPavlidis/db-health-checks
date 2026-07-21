-- ============================================================
-- Health Check: Ch 19 Availability Groups — 19.1 AG Inventory and Replica State
-- Checklist ref: Section 19.1
-- Min SQL version: 2016 (130)
-- ============================================================
-- Returns per-replica configuration and current health state for all AGs.
-- Flags disconnected or unhealthy replicas for immediate attention.
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

IF CAST(SERVERPROPERTY('IsHadrEnabled') AS INT) = 0
BEGIN
    SELECT 'HADR not enabled on this instance' AS Note; RETURN;
END
GO

SELECT
    ag.name                                         AS AGName,
    ag.group_id                                     AS AGGroupId,
    ag.cluster_type_desc                            AS ClusterType,
    ag.automated_backup_preference_desc             AS AutomatedBackupPreference,
    ag.failure_condition_level                      AS FailureConditionLevel,
    ag.health_check_timeout                         AS HealthCheckTimeoutMs,
    ar.replica_server_name                          AS ReplicaServer,
    ar.endpoint_url                                 AS EndpointUrl,
    ar.availability_mode_desc                       AS AvailabilityMode,
    ar.failover_mode_desc                           AS FailoverMode,
    ar.seeding_mode_desc                            AS SeedingMode,
    ar.backup_priority                              AS BackupPriority,
    ar.session_timeout                              AS SessionTimeoutSec,
    ars.role_desc                                   AS CurrentRole,
    ars.operational_state_desc                      AS OperationalState,
    ars.connected_state_desc                        AS ConnectedState,
    ars.synchronization_health_desc                 AS SyncHealth,
    ars.last_connect_error_number                   AS LastConnectErrorNumber,
    ars.last_connect_error_description              AS LastConnectErrorDesc,
    ars.last_connect_error_timestamp                AS LastConnectErrorTime,
    CASE WHEN ars.connected_state_desc <> 'CONNECTED'           THEN 'DISCONNECTED_REPLICA'
         WHEN ars.synchronization_health_desc <> 'HEALTHY'      THEN 'UNHEALTHY_REPLICA'
         ELSE ''
    END                                             AS ReplicaFlag
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar
    ON ar.group_id = ag.group_id
JOIN sys.dm_hadr_availability_replica_states ars
    ON ars.replica_id = ar.replica_id
ORDER BY ag.name, ar.replica_server_name;
