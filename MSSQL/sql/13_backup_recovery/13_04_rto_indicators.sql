-- ============================================================
-- Health Check: Ch 13 Backup and Recovery — 13.4 RTO Risk Indicators
-- Checklist ref: Section 13.4
-- Min SQL version: 2016 (130)
-- Note: RTO indicators only. Actual RTO cannot be validated without
--       recovery or failover testing.
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- ── Section A: Database size, recovery settings, and last full backup duration ─

;WITH DataFileSizes AS (
    SELECT
        mf.database_id,
        SUM(CAST(mf.size AS BIGINT) * 8 / 1024)            AS DataSizeMB
    FROM sys.master_files mf
    WHERE mf.type_desc = 'ROWS'
    GROUP BY mf.database_id
),
LatestFullBackup AS (
    SELECT
        bs.database_name,
        MAX(bs.backup_finish_date)                          AS LastFullFinish
    FROM msdb.dbo.backupset bs
    WHERE bs.type = 'D'
    GROUP BY bs.database_name
),
FullBackupDetail AS (
    SELECT
        bs.database_name,
        bs.backup_finish_date,
        DATEDIFF(SECOND, bs.backup_start_date, bs.backup_finish_date) AS LastFullDurationSec
    FROM msdb.dbo.backupset bs
    INNER JOIN LatestFullBackup lf
        ON  bs.database_name    = lf.database_name
        AND bs.backup_finish_date = lf.LastFullFinish
        AND bs.type             = 'D'
),
LogBackupVolume24h AS (
    SELECT
        bs.database_name,
        SUM(CAST(bs.backup_size AS BIGINT)) / 1048576       AS LogBackupSizeMB24h,
        COUNT(*)                                            AS LogBackupCount24h
    FROM msdb.dbo.backupset bs
    WHERE bs.type               = 'L'
      AND bs.backup_finish_date >= DATEADD(HOUR, -24, GETDATE())
    GROUP BY bs.database_name
)
SELECT
    d.name                                                  AS [DatabaseName],
    d.recovery_model_desc                                   AS [RecoveryModel],
    d.target_recovery_time_in_seconds                       AS [TargetRecoveryTimeSec],
    CASE
        WHEN d.target_recovery_time_in_seconds > 0 THEN 1
        ELSE 0
    END                                                     AS [IndirectCheckpointEnabled],
    dfs.DataSizeMB                                          AS [DataSizeMB],
    fbd.backup_finish_date                                  AS [LastFullBackupFinish],
    fbd.LastFullDurationSec                                 AS [LastFullDurationSec],
    lbv.LogBackupSizeMB24h                                  AS [LogBackupVolumeMB24h],
    lbv.LogBackupCount24h                                   AS [LogBackupCount24h]
FROM sys.databases d
LEFT JOIN DataFileSizes       dfs ON dfs.database_id  = d.database_id
LEFT JOIN FullBackupDetail    fbd ON fbd.database_name = d.name
LEFT JOIN LogBackupVolume24h  lbv ON lbv.database_name = d.name
WHERE d.state_desc  = 'ONLINE'
  AND d.database_id > 4
ORDER BY d.name;

GO

-- ── Section B: VLF count per database (dynamic SQL cursor over sys.databases) ──
-- High VLF counts increase crash-recovery and restore time.

DECLARE @dbName    NVARCHAR(128);
DECLARE @sql       NVARCHAR(512);
DECLARE @vlfCount  INT;

CREATE TABLE #VlfCounts (
    DatabaseName  NVARCHAR(128) NOT NULL,
    VlfCount      INT           NOT NULL
);

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM sys.databases
    WHERE state_desc = 'ONLINE'
      AND database_id > 4;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @dbName;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- SQL 2016+ DBCC LOGINFO returns a result set; count rows per database.
    -- We insert into a temp table via INSERT...EXEC.
    BEGIN TRY
        CREATE TABLE #LogInfoTemp (
            RecoveryUnitId  INT,
            FileId          INT,
            FileSize        BIGINT,
            StartOffset     BIGINT,
            FSeqNo          INT,
            [Status]        INT,
            Parity          TINYINT,
            CreateLSN       NUMERIC(25,0)
        );

        SET @sql = N'DBCC LOGINFO(' + QUOTENAME(@dbName, N'''') + N') WITH NO_INFOMSGS;';
        INSERT INTO #LogInfoTemp
        EXEC sp_executesql @sql;

        SELECT @vlfCount = COUNT(*) FROM #LogInfoTemp;
        DROP TABLE #LogInfoTemp;

        INSERT INTO #VlfCounts (DatabaseName, VlfCount)
        VALUES (@dbName, @vlfCount);
    END TRY
    BEGIN CATCH
        INSERT INTO #VlfCounts (DatabaseName, VlfCount)
        VALUES (@dbName, -1);   -- -1 indicates collection failure
    END CATCH;

    FETCH NEXT FROM db_cursor INTO @dbName;
END;

CLOSE db_cursor;
DEALLOCATE db_cursor;

SELECT
    DatabaseName                                            AS [DatabaseName],
    VlfCount                                                AS [VlfCount],
    CASE
        WHEN VlfCount  < 0    THEN 'CollectionError'
        WHEN VlfCount  < 100  THEN 'OK'
        WHEN VlfCount  < 500  THEN 'Moderate'
        WHEN VlfCount  < 1000 THEN 'High'
        ELSE                       'Critical'
    END                                                     AS [VlfRating]
FROM #VlfCounts
ORDER BY VlfCount DESC;

DROP TABLE #VlfCounts;

GO

-- ── Section C: AG failover mode, sync state, redo queue, and redo rate ─────────
-- Only executed when HADR is enabled on this instance.

IF CAST(SERVERPROPERTY('IsHadrEnabled') AS INT) = 1
BEGIN
    SELECT
        ag.name                                             AS [AGName],
        d.name                                              AS [DatabaseName],
        ar.replica_server_name                              AS [ReplicaServer],
        ar.availability_mode_desc                           AS [AvailabilityMode],
        ar.failover_mode_desc                               AS [FailoverMode],
        drs.synchronization_state_desc                      AS [SynchronizationState],
        drs.synchronization_health_desc                     AS [SynchronizationHealth],
        drs.redo_queue_size                                 AS [RedoQueueSizeKB],
        drs.redo_rate                                       AS [RedoRateKBPerSec],
        drs.log_send_queue_size                             AS [LogSendQueueSizeKB],
        drs.log_send_rate                                   AS [LogSendRateKBPerSec],
        drs.is_local                                        AS [IsLocalReplica],
        drs.is_primary_replica                              AS [IsPrimaryReplica],
        drs.last_redone_time                                AS [LastRedoneTime],
        drs.last_received_time                              AS [LastReceivedTime]
    FROM sys.availability_groups ag
    INNER JOIN sys.availability_replicas ar
        ON ar.group_id = ag.group_id
    INNER JOIN sys.dm_hadr_database_replica_states drs
        ON  drs.group_id         = ar.group_id
        AND drs.replica_id       = ar.replica_id
    INNER JOIN sys.databases d
        ON  d.replica_id         = drs.replica_id
        AND d.group_database_id  = drs.group_database_id
    ORDER BY
        ag.name,
        d.name,
        ar.replica_server_name;
END
ELSE
BEGIN
    SELECT 'HADR not enabled on this instance — AG indicators skipped.' AS [Note];
END;
