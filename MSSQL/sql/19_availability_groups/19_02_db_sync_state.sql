-- ============================================================
-- Health Check: Ch 19 Availability Groups — 19.2 Database Synchronization State
-- Checklist ref: Section 19.2
-- Min SQL version: 2016 (130)
-- ============================================================
-- Returns per-database synchronization state across all AG replicas.
-- Flags databases that are not synchronizing or have been suspended.
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
    d.name                                          AS DatabaseName,
    drs.is_local                                    AS IsLocal,
    drs.is_primary_replica                          AS IsPrimaryReplica,
    drs.synchronization_state_desc                  AS SyncState,
    drs.synchronization_health_desc                 AS SyncHealth,
    drs.database_state_desc                         AS DatabaseState,
    drs.is_suspended                                AS IsSuspended,
    drs.suspend_reason_desc                         AS SuspendReason,
    drs.is_commit_participant                       AS IsCommitParticipant,
    drs.last_sent_time                              AS LastSentTime,
    drs.last_received_time                          AS LastReceivedTime,
    drs.last_hardened_time                          AS LastHardenedTime,
    drs.last_redone_time                            AS LastRedonetime,
    drs.last_commit_time                            AS LastCommitTime,
    ar.replica_server_name                          AS ReplicaServer,
    CASE WHEN drs.synchronization_state_desc <> 'SYNCHRONIZED'
              AND drs.synchronization_state_desc <> 'SYNCHRONIZING'
              THEN 'NOT_SYNCHRONIZING'
         WHEN drs.is_suspended = 1
              THEN 'SUSPENDED'
         ELSE ''
    END                                             AS DBFlag
FROM sys.dm_hadr_database_replica_states drs
JOIN sys.availability_replicas ar
    ON ar.replica_id = drs.replica_id
JOIN sys.availability_groups ag
    ON ag.group_id = ar.group_id
JOIN sys.databases d
    ON d.group_database_id = drs.group_database_id
ORDER BY ag.name, d.name, ar.replica_server_name;
