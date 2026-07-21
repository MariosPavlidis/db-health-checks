-- ============================================================
-- Health Check: Ch 13 Backup and Recovery — 13.2 Backup Chain Integrity
-- Checklist ref: Section 13.2
-- Min SQL version: 2016 (130)
-- Note: This check does not validate backup-file usability or restorability.
--       LSN chain verification here is metadata-only and indicates potential
--       chain breaks; actual restore testing is required to confirm integrity.
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

;WITH BackupHistory AS (
    SELECT
        bs.database_name,
        bs.backup_start_date,
        bs.backup_finish_date,
        bs.type,
        bs.first_lsn,
        bs.last_lsn,
        bs.checkpoint_lsn,
        bs.database_backup_lsn,
        bs.differential_base_lsn,
        bs.first_recovery_fork_guid     AS fork_guid,
        bs.last_recovery_fork_guid      AS recovery_fork_guid,
        bs.is_copy_only,
        bs.recovery_model,
        bs.backup_set_id,
        -- Previous log backup's last_lsn (for LSN gap detection on log backups)
        LAG(bs.last_lsn) OVER (
            PARTITION BY bs.database_name, bs.type
            ORDER BY bs.backup_start_date
        )                                                   AS PrevLogLastLsn,
        -- Previous row's recovery_model (for recovery model change detection)
        LAG(bs.recovery_model) OVER (
            PARTITION BY bs.database_name
            ORDER BY bs.backup_start_date
        )                                                   AS PrevRecoveryModel,
        -- Most recent full backup last_lsn at the time of each differential
        -- (to check differential_base_lsn alignment)
        MAX(CASE WHEN bs.type = 'D' AND bs.is_copy_only = 0
                 THEN bs.last_lsn END)
            OVER (
                PARTITION BY bs.database_name
                ORDER BY bs.backup_start_date
                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
            )                                               AS LastFullLastLsn
    FROM msdb.dbo.backupset bs
    WHERE bs.backup_start_date >= DATEADD(DAY, -30, GETDATE())
),
Anomalies AS (
    -- LSN gap: log backup first_lsn does not match previous log backup's last_lsn
    SELECT
        database_name, backup_start_date, backup_finish_date, type,
        first_lsn, last_lsn, checkpoint_lsn, database_backup_lsn,
        differential_base_lsn, fork_guid, recovery_fork_guid, is_copy_only,
        recovery_model,
        'LSN Gap: first_lsn (' + CAST(first_lsn AS VARCHAR(50))
            + ') does not match previous log last_lsn ('
            + CAST(PrevLogLastLsn AS VARCHAR(50)) + ')'    AS [Note]
    FROM BackupHistory
    WHERE type          = 'L'
      AND PrevLogLastLsn IS NOT NULL
      AND first_lsn     <> PrevLogLastLsn

    UNION ALL

    -- Recovery model change between consecutive backup entries
    SELECT
        database_name, backup_start_date, backup_finish_date, type,
        first_lsn, last_lsn, checkpoint_lsn, database_backup_lsn,
        differential_base_lsn, fork_guid, recovery_fork_guid, is_copy_only,
        recovery_model,
        'Recovery Model Change: was ' + CAST(PrevRecoveryModel AS VARCHAR(20))
            + ', now ' + CAST(recovery_model AS VARCHAR(20))
    FROM BackupHistory
    WHERE PrevRecoveryModel IS NOT NULL
      AND recovery_model    <> PrevRecoveryModel

    UNION ALL

    -- Differential base inconsistency: differential_base_lsn doesn't match
    -- the most recent non-copy-only full backup's last_lsn
    SELECT
        database_name, backup_start_date, backup_finish_date, type,
        first_lsn, last_lsn, checkpoint_lsn, database_backup_lsn,
        differential_base_lsn, fork_guid, recovery_fork_guid, is_copy_only,
        recovery_model,
        'Differential Base Mismatch: differential_base_lsn ('
            + CAST(differential_base_lsn AS VARCHAR(50))
            + ') does not match last full backup last_lsn ('
            + CAST(LastFullLastLsn AS VARCHAR(50)) + ')'
    FROM BackupHistory
    WHERE type            = 'I'
      AND LastFullLastLsn IS NOT NULL
      AND differential_base_lsn <> LastFullLastLsn

    UNION ALL

    -- Copy-only full backup flag (informational — does not break the chain
    -- but may indicate ad-hoc activity worth reviewing)
    SELECT
        database_name, backup_start_date, backup_finish_date, type,
        first_lsn, last_lsn, checkpoint_lsn, database_backup_lsn,
        differential_base_lsn, fork_guid, recovery_fork_guid, is_copy_only,
        recovery_model,
        'Copy-Only Full Backup: does not reset differential base'
    FROM BackupHistory
    WHERE type       = 'D'
      AND is_copy_only = 1
)
SELECT
    database_name                                           AS [DatabaseName],
    backup_start_date                                       AS [BackupStartDate],
    backup_finish_date                                      AS [BackupFinishDate],
    CASE type
        WHEN 'D' THEN 'Full'
        WHEN 'I' THEN 'Differential'
        WHEN 'L' THEN 'Log'
        ELSE type
    END                                                     AS [BackupType],
    type                                                    AS [BackupTypeCode],
    first_lsn                                               AS [FirstLsn],
    last_lsn                                                AS [LastLsn],
    checkpoint_lsn                                          AS [CheckpointLsn],
    database_backup_lsn                                     AS [DatabaseBackupLsn],
    differential_base_lsn                                   AS [DifferentialBaseLsn],
    fork_guid                                               AS [ForkGuid],
    recovery_fork_guid                                      AS [RecoveryForkGuid],
    is_copy_only                                            AS [IsCopyOnly],
    recovery_model                                          AS [RecoveryModel],
    [Note]
FROM Anomalies
ORDER BY
    database_name,
    backup_start_date DESC;
