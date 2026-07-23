-- ============================================================
-- Health Check: Ch 19 Availability Groups — 19.10 Data-Loss Exposure and Failover Readiness
-- Checklist ref: Section 19.10
-- Min SQL version: 2016 (130)
-- ============================================================
-- Query 1: Asynchronous replicas — redo_queue_size represents the maximum
--           data-loss exposure in KB if the primary fails right now.
--           Estimated exposure in seconds is derived from redo_rate where available.
-- Query 2: Synchronous replicas — flags replicas that are configured for
--           AUTOMATIC failover but are NOT currently failover-ready
--           (not SYNCHRONIZED or not CONNECTED).
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

-- ── 1. Async replica data-loss exposure ──────────────────────────────────────
SELECT
    ag.name                                         AS AGName,
    ar.replica_server_name                          AS ReplicaServer,
    ar.availability_mode_desc                       AS AvailabilityMode,
    ar.failover_mode_desc                           AS FailoverMode,
    d.name                                          AS DatabaseName,
    drs.synchronization_state_desc                  AS SyncState,
    drs.redo_queue_size                             AS RedoQueueKB,
    drs.redo_rate                                   AS RedoRateKBperSec,
    -- Estimated seconds of data that would be lost if primary fails now
    CASE WHEN drs.redo_rate > 0
         THEN CAST(drs.redo_queue_size * 1.0 / drs.redo_rate AS DECIMAL(10,1))
         ELSE NULL
    END                                             AS EstDataLossExposureSec,
    CASE
        WHEN drs.redo_queue_size > 524288           THEN 'DATA_LOSS_HIGH'   -- > 512 MB
        WHEN drs.redo_queue_size > 102400           THEN 'DATA_LOSS_WARN'   -- > 100 MB
        WHEN drs.redo_queue_size > 0
             AND drs.redo_rate = 0                  THEN 'ZERO_REDO_RATE'
        ELSE ''
    END                                             AS DataLossFlag
FROM sys.dm_hadr_database_replica_states drs
JOIN sys.availability_replicas ar
    ON ar.replica_id = drs.replica_id
JOIN sys.availability_groups ag
    ON ag.group_id = ar.group_id
JOIN sys.databases d
    ON d.group_database_id = drs.group_database_id
WHERE drs.is_local = 0
  AND ar.availability_mode_desc = 'ASYNCHRONOUS_COMMIT'
ORDER BY drs.redo_queue_size DESC;

-- ── 2. Sync replica automatic-failover readiness ─────────────────────────────
SELECT
    ag.name                                         AS AGName,
    ar.replica_server_name                          AS ReplicaServer,
    ar.availability_mode_desc                       AS AvailabilityMode,
    ar.failover_mode_desc                           AS FailoverMode,
    ars.role_desc                                   AS CurrentRole,
    ars.connected_state_desc                        AS ConnectedState,
    ars.synchronization_health_desc                 AS SyncHealth,
    -- Count synchronized vs total databases on this replica
    (SELECT COUNT(*)
     FROM sys.dm_hadr_database_replica_states drs2
     WHERE drs2.replica_id = ar.replica_id
       AND drs2.synchronization_state_desc = 'SYNCHRONIZED') AS DBsSynchronized,
    (SELECT COUNT(*)
     FROM sys.dm_hadr_database_replica_states drs2
     WHERE drs2.replica_id = ar.replica_id)         AS DBsTotal,
    CASE
        WHEN ar.failover_mode_desc = 'AUTOMATIC'
             AND ars.connected_state_desc = 'CONNECTED'
             AND ars.synchronization_health_desc = 'HEALTHY'
             THEN 'FAILOVER_READY'
        WHEN ar.failover_mode_desc = 'AUTOMATIC'
             AND ars.connected_state_desc <> 'CONNECTED'
             THEN 'NOT_READY_DISCONNECTED'
        WHEN ar.failover_mode_desc = 'AUTOMATIC'
             AND ars.synchronization_health_desc <> 'HEALTHY'
             THEN 'NOT_READY_UNHEALTHY'
        WHEN ar.failover_mode_desc = 'MANUAL'
             THEN 'MANUAL_FAILOVER_ONLY'
        ELSE ''
    END                                             AS FailoverReadiness
FROM sys.availability_replicas ar
JOIN sys.availability_groups ag
    ON ag.group_id = ar.group_id
JOIN sys.dm_hadr_availability_replica_states ars
    ON ars.replica_id = ar.replica_id
WHERE ar.availability_mode_desc = 'SYNCHRONOUS_COMMIT'
  AND ars.role_desc = 'SECONDARY'
ORDER BY ag.name, ar.replica_server_name;
