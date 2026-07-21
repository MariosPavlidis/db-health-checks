-- ============================================================
-- Health Check: Ch 19 Availability Groups — 19.3 Send and Redo Queue Depths
-- Checklist ref: Section 19.3
-- Min SQL version: 2016 (130)
-- ============================================================
-- Reports log send and redo queue sizes with estimated catch-up times
-- for secondary replicas. Flags queues exceeding 1 GB or with zero
-- throughput while data is outstanding.
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
    ar.replica_server_name                          AS ReplicaServer,
    d.name                                          AS DatabaseName,
    drs.log_send_queue_size                         AS LogSendQueueKB,
    drs.log_send_rate                               AS LogSendRateKBperSec,
    drs.redo_queue_size                             AS RedoQueueKB,
    drs.redo_rate                                   AS RedoRateKBperSec,
    -- Estimated catch-up times
    CASE WHEN drs.log_send_rate > 0
         THEN CAST(drs.log_send_queue_size / drs.log_send_rate AS DECIMAL(10,1))
         ELSE NULL
    END                                             AS EstSendCatchUpSec,
    CASE WHEN drs.redo_rate > 0
         THEN CAST(drs.redo_queue_size / drs.redo_rate AS DECIMAL(10,1))
         ELSE NULL
    END                                             AS EstRedoCatchUpSec,
    drs.last_sent_time                              AS LastSentTime,
    drs.last_redone_time                            AS LastRedonetime,
    -- Flags
    CASE WHEN drs.log_send_queue_size > 1048576     THEN 'SEND_QUEUE_HIGH'    -- > 1 GB
         WHEN drs.log_send_rate = 0
              AND drs.log_send_queue_size > 0       THEN 'ZERO_SEND_RATE'
         ELSE ''
    END                                             AS SendQueueFlag,
    CASE WHEN drs.redo_queue_size > 1048576         THEN 'REDO_QUEUE_HIGH'    -- > 1 GB
         WHEN drs.redo_rate = 0
              AND drs.redo_queue_size > 0           THEN 'ZERO_REDO_RATE'
         ELSE ''
    END                                             AS RedoQueueFlag
FROM sys.dm_hadr_database_replica_states drs
JOIN sys.availability_replicas ar
    ON ar.replica_id = drs.replica_id
JOIN sys.availability_groups ag
    ON ag.group_id = ar.group_id
JOIN sys.databases d
    ON d.group_database_id = drs.group_database_id
WHERE drs.is_local = 0  -- secondary replicas
ORDER BY drs.log_send_queue_size DESC;
