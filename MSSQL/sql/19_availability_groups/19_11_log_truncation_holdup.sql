-- ============================================================
-- Health Check: Ch 19 Availability Groups — 19.11 Log Truncation Holdup by AG Replica
-- Checklist ref: Section 19.11
-- Min SQL version: 2016 (130)
-- ============================================================
-- Identifies databases whose transaction log cannot be truncated because an AG
-- secondary replica is lagging (log_reuse_wait_desc = 'AVAILABILITY_REPLICA').
-- Reports the log send queue size per secondary to identify the source of the holdup.
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
    d.name                                          AS DatabaseName,
    d.log_reuse_wait_desc                           AS LogReuseWait,
    ag.name                                         AS AGName,
    ar.replica_server_name                          AS ReplicaServer,
    ar.availability_mode_desc                       AS AvailabilityMode,
    drs.synchronization_state_desc                  AS SyncState,
    drs.log_send_queue_size                         AS LogSendQueueKB,
    drs.log_send_rate                               AS LogSendRateKBperSec,
    CASE WHEN drs.log_send_rate > 0
         THEN CAST(drs.log_send_queue_size * 1.0 / drs.log_send_rate AS DECIMAL(10,1))
         ELSE NULL
    END                                             AS EstCatchUpSec,
    drs.last_sent_time                              AS LastSentTime,
    CASE
        WHEN drs.log_send_queue_size > 1048576      THEN 'HOLDUP_CRITICAL'  -- > 1 GB
        WHEN drs.log_send_queue_size > 102400       THEN 'HOLDUP_HIGH'      -- > 100 MB
        WHEN drs.log_send_queue_size > 0
             AND drs.log_send_rate = 0              THEN 'ZERO_SEND_RATE'
        ELSE 'HOLDUP_MINOR'
    END                                             AS HoldupFlag
FROM sys.databases d
JOIN sys.dm_hadr_database_replica_states drs
    ON drs.group_database_id = d.group_database_id
   AND drs.is_local = 0                            -- secondary replicas only
JOIN sys.availability_replicas ar
    ON ar.replica_id = drs.replica_id
JOIN sys.availability_groups ag
    ON ag.group_id = ar.group_id
WHERE d.log_reuse_wait_desc = 'AVAILABILITY_REPLICA'
ORDER BY drs.log_send_queue_size DESC, d.name;
