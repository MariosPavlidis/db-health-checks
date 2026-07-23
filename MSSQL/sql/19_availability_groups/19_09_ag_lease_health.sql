-- ============================================================
-- Health Check: Ch 19 Availability Groups — 19.9 Lease and Session Timeout Health
-- Checklist ref: Section 19.9
-- Min SQL version: 2016 (130)
-- ============================================================
-- Reports AG failure-condition level, health-check timeout, per-replica session
-- timeout, and current connectivity/recovery state.  Disconnected replicas with
-- recent connect errors may indicate lease expiry or network disruption.
-- Review 19_06_ag_errors.sql for error-log evidence of lease-expiration events.
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
    -- AG-level lease/health parameters
    ag.failure_condition_level                      AS FailureConditionLevel,
    ag.health_check_timeout                         AS HealthCheckTimeoutMs,
    ag.db_failover                                  AS DatabaseLevelFailoverEnabled,
    -- Replica-level session timeout (lease is ≈ session_timeout / 3)
    ar.replica_server_name                          AS ReplicaServer,
    ar.session_timeout                              AS SessionTimeoutSec,
    ar.endpoint_url                                 AS EndpointUrl,
    ar.availability_mode_desc                       AS AvailabilityMode,
    -- Current runtime state
    ars.role_desc                                   AS CurrentRole,
    ars.operational_state_desc                      AS OperationalState,
    ars.connected_state_desc                        AS ConnectedState,
    ars.recovery_health_desc                        AS RecoveryHealth,
    ars.synchronization_health_desc                 AS SyncHealth,
    -- Recent connection errors
    ars.last_connect_error_number                   AS LastConnectErrorNumber,
    ars.last_connect_error_description              AS LastConnectErrorDesc,
    ars.last_connect_error_timestamp                AS LastConnectErrorTime,
    -- Flag: disconnected replicas or recent errors (possible lease/network event)
    CASE
        WHEN ars.connected_state_desc = 'DISCONNECTED'
             AND ars.last_connect_error_timestamp >= DATEADD(HOUR, -24, GETDATE())
             THEN 'RECENT_DISCONNECT'
        WHEN ars.connected_state_desc = 'DISCONNECTED'
             THEN 'DISCONNECTED'
        WHEN ars.operational_state_desc NOT IN ('ONLINE', 'ONLINE_IN_PROGRESS')
             AND ars.role_desc <> 'RESOLVING'
             THEN 'OPERATIONAL_STATE_WARN'
        WHEN ars.last_connect_error_timestamp >= DATEADD(HOUR, -24, GETDATE())
             AND ars.connected_state_desc = 'CONNECTED'
             THEN 'RECENT_ERROR_NOW_CONNECTED'
        ELSE ''
    END                                             AS LeaseHealthFlag
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar
    ON ar.group_id = ag.group_id
JOIN sys.dm_hadr_availability_replica_states ars
    ON ars.replica_id = ar.replica_id
ORDER BY ag.name, ar.replica_server_name;
