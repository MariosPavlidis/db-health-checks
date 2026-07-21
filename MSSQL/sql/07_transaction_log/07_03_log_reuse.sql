-- ============================================================
-- Health Check: Ch 07 Transaction Log — 7.3 Log Reuse Wait Analysis
-- Checklist ref: Section 7.3
-- Min SQL version: 2016 (130)
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- ── Part 1: Databases grouped by log_reuse_wait category ─────────────────────
-- Key categories and what they mean:
--   NOTHING             : Log can be reused — healthy state
--   LOG_BACKUP          : FULL/BULK_LOGGED recovery but no log backup has been taken recently
--   ACTIVE_TRANSACTION  : An open transaction is preventing truncation
--   AVAILABILITY_REPLICA: An AG secondary replica has not received/hardened the log
--   REPLICATION         : A replication reader has not consumed log records
--   OLDEST_PAGE         : Indirect checkpoint is waiting for a dirty page flush
--   DATABASE_SNAPSHOT_CREATION : A snapshot is being created
--   OTHER               : Catch-all; may include LOG_SCAN, ACTIVE_BACKUP_OR_RESTORE, etc.

SELECT
    d.name                                          AS DatabaseName,
    d.recovery_model_desc                           AS RecoveryModel,
    d.log_reuse_wait                                AS LogReuseWaitCode,
    d.log_reuse_wait_desc                           AS LogReuseWaitDesc,
    -- Advisory per category
    CASE d.log_reuse_wait_desc
        WHEN 'LOG_BACKUP'
            THEN 'Take a transaction log backup immediately; schedule regular log backups'
        WHEN 'ACTIVE_TRANSACTION'
            THEN 'Identify and commit or roll back the long-running open transaction'
        WHEN 'AVAILABILITY_REPLICA'
            THEN 'Check AG secondary health and network latency; look for redo queue backlog'
        WHEN 'REPLICATION'
            THEN 'Check replication reader agent; consider marking DB for replication if no longer used'
        WHEN 'OLDEST_PAGE'
            THEN 'Indirect checkpoint is waiting on a dirty page; check I/O subsystem performance'
        WHEN 'DATABASE_SNAPSHOT_CREATION'
            THEN 'Snapshot creation in progress; wait for it to complete'
        WHEN 'NOTHING'
            THEN 'Log reuse is not blocked — healthy'
        ELSE 'Review log_reuse_wait_desc documentation for this category'
    END                                             AS Advisory,
    d.state_desc                                    AS DatabaseState,
    -- Flag: FULL recovery without a recent log backup
    CASE
        WHEN d.recovery_model_desc IN ('FULL', 'BULK_LOGGED')
         AND d.log_reuse_wait_desc = 'LOG_BACKUP'
        THEN 'Y'
        ELSE 'N'
    END                                             AS FullRecoveryBlockedByLogBackup
FROM sys.databases d
WHERE d.state_desc = 'ONLINE'
ORDER BY
    -- Most urgent states first
    CASE d.log_reuse_wait_desc
        WHEN 'LOG_BACKUP'              THEN 1
        WHEN 'ACTIVE_TRANSACTION'      THEN 2
        WHEN 'AVAILABILITY_REPLICA'    THEN 3
        WHEN 'REPLICATION'             THEN 4
        WHEN 'OLDEST_PAGE'             THEN 5
        WHEN 'DATABASE_SNAPSHOT_CREATION' THEN 6
        WHEN 'NOTHING'                 THEN 99
        ELSE 50
    END,
    d.name;

GO

-- ── Part 2: Sessions with open transactions (potential ACTIVE_TRANSACTION cause) ──
-- Cross-reference: sessions that have an open transaction joined to exec_sessions.
SELECT
    st.session_id,
    st.transaction_id,
    st.is_user_transaction,
    st.open_transaction_count,
    es.login_name,
    es.host_name,
    es.program_name,
    es.status                                       AS SessionStatus,
    es.last_request_start_time,
    es.last_request_end_time,
    DATEDIFF(SECOND, es.last_request_start_time, GETDATE())
                                                    AS SecondsSinceLastRequest,
    at.name                                         AS TransactionName,
    at.transaction_begin_time,
    DATEDIFF(MINUTE, at.transaction_begin_time, GETDATE())
                                                    AS TransactionAgeMinutes,
    at.transaction_type,
    at.transaction_state
FROM sys.dm_tran_session_transactions               st
JOIN sys.dm_exec_sessions                           es  ON es.session_id     = st.session_id
JOIN sys.dm_tran_active_transactions                at  ON at.transaction_id = st.transaction_id
WHERE st.is_user_transaction = 1
  AND at.transaction_state IN (2, 5)   -- active or prepared
ORDER BY at.transaction_begin_time ASC;

GO

-- ── Part 3: FULL-recovery databases without a recent log backup ───────────────
-- Cross-references msdb.dbo.backupset to identify log backup gaps.
SELECT
    d.name                                          AS DatabaseName,
    d.recovery_model_desc                           AS RecoveryModel,
    d.log_reuse_wait_desc                           AS LogReuseWaitDesc,
    llb.LastLogBackupDate,
    DATEDIFF(MINUTE, llb.LastLogBackupDate, GETDATE())
                                                    AS MinutesSinceLastLogBackup,
    CASE
        WHEN llb.LastLogBackupDate IS NULL
            THEN 'NEVER_BACKED_UP'
        WHEN llb.LastLogBackupDate < DATEADD(HOUR, -24, GETDATE())
            THEN 'NO_BACKUP_LAST_24H'
        WHEN llb.LastLogBackupDate < DATEADD(HOUR, -1, GETDATE())
            THEN 'NO_BACKUP_LAST_1H'
        ELSE 'OK'
    END                                             AS LogBackupStatus
FROM sys.databases                                  d
LEFT JOIN (
    SELECT
        database_name,
        MAX(backup_finish_date)                     AS LastLogBackupDate
    FROM msdb.dbo.backupset
    WHERE type = 'L'
    GROUP BY database_name
)                                                   llb ON llb.database_name = d.name
WHERE d.state_desc      = 'ONLINE'
  AND d.recovery_model_desc IN ('FULL', 'BULK_LOGGED')
  AND d.name NOT IN ('master', 'msdb', 'model')    -- system dbs typically SIMPLE
ORDER BY
    CASE
        WHEN llb.LastLogBackupDate IS NULL THEN 1
        WHEN llb.LastLogBackupDate < DATEADD(HOUR, -24, GETDATE()) THEN 2
        WHEN llb.LastLogBackupDate < DATEADD(HOUR, -1, GETDATE()) THEN 3
        ELSE 4
    END,
    d.name;
