-- ============================================================
-- Health Check: Ch 19 Availability Groups — 19.13 Distributed Availability Group Inventory
-- Checklist ref: Section 19.13
-- Min SQL version: 2016 (130)
-- ============================================================
-- Lists Distributed Availability Groups (is_distributed = 1) and the member
-- AGs (replicas) with their current connectivity and synchronization health.
-- Returns no rows if no Distributed AGs are configured.
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

-- ── Distributed AG inventory and member AG health ────────────────────────────
SELECT
    ag.name                                         AS DAGName,
    ag.group_id                                     AS DAGGroupId,
    ag.cluster_type_desc                            AS ClusterType,
    ag.failure_condition_level                      AS FailureConditionLevel,
    ag.automated_backup_preference_desc             AS BackupPreference,
    ar.replica_server_name                          AS MemberAGEndpointName,
    ar.endpoint_url                                 AS EndpointUrl,
    ar.availability_mode_desc                       AS AvailabilityMode,
    ar.failover_mode_desc                           AS FailoverMode,
    ars.role_desc                                   AS CurrentRole,
    ars.operational_state_desc                      AS OperationalState,
    ars.connected_state_desc                        AS ConnectedState,
    ars.synchronization_health_desc                 AS SyncHealth,
    ars.last_connect_error_number                   AS LastConnectErrorNumber,
    ars.last_connect_error_description              AS LastConnectErrorDesc,
    ars.last_connect_error_timestamp                AS LastConnectErrorTime,
    CASE
        WHEN ars.connected_state_desc <> 'CONNECTED'       THEN 'MEMBER_AG_DISCONNECTED'
        WHEN ars.synchronization_health_desc <> 'HEALTHY'  THEN 'MEMBER_AG_UNHEALTHY'
        ELSE ''
    END                                             AS DAGHealthFlag
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar
    ON ar.group_id = ag.group_id
JOIN sys.dm_hadr_availability_replica_states ars
    ON ars.replica_id = ar.replica_id
WHERE ag.is_distributed = 1
ORDER BY ag.name, ar.replica_server_name;
