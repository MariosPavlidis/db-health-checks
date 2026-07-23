-- =============================================================================
-- Health Check: Ch 22 Maintenance and Operational Governance — 22.4 CDC Inventory
-- Checklist ref: Section 22.4
-- Min SQL version: SQL Server 2016
--
-- Result sets:
--   1. CDC state and Agent-job coverage by database
--   2. CDC capture-instance inventory
--   3. CDC capture and cleanup job configuration and last outcome
-- =============================================================================
SET NOCOUNT ON;

IF TRY_CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT
        'VERSION_GUARD' AS ResultSetName,
        'Requires SQL Server 2016 or later.' AS Note;
    RETURN;
END;

CREATE TABLE #CdcJobSummary
(
    DatabaseId          INT NOT NULL PRIMARY KEY,
    CaptureJobCount     INT NOT NULL,
    CleanupJobCount     INT NOT NULL,
    ExistingCaptureJobs INT NOT NULL,
    ExistingCleanupJobs INT NOT NULL,
    DisabledJobCount    INT NOT NULL,
    FailedJobCount      INT NOT NULL
);

IF OBJECT_ID(N'msdb.dbo.cdc_jobs') IS NOT NULL
BEGIN
    INSERT #CdcJobSummary
    (
        DatabaseId,
        CaptureJobCount,
        CleanupJobCount,
        ExistingCaptureJobs,
        ExistingCleanupJobs,
        DisabledJobCount,
        FailedJobCount
    )
    SELECT
        cj.database_id,
        SUM(CASE WHEN cj.job_type = N'capture' THEN 1 ELSE 0 END),
        SUM(CASE WHEN cj.job_type = N'cleanup' THEN 1 ELSE 0 END),
        SUM(CASE WHEN cj.job_type = N'capture' AND j.job_id IS NOT NULL THEN 1 ELSE 0 END),
        SUM(CASE WHEN cj.job_type = N'cleanup' AND j.job_id IS NOT NULL THEN 1 ELSE 0 END),
        SUM(CASE WHEN j.job_id IS NOT NULL AND j.enabled = 0 THEN 1 ELSE 0 END),
        SUM(CASE WHEN sjs.last_run_outcome IN (0, 2, 3) THEN 1 ELSE 0 END)
    FROM msdb.dbo.cdc_jobs AS cj
    LEFT JOIN msdb.dbo.sysjobs AS j
        ON j.job_id = cj.job_id
    LEFT JOIN msdb.dbo.sysjobservers AS sjs
        ON sjs.job_id = cj.job_id
       AND sjs.server_id = 0
    GROUP BY cj.database_id;
END;

SELECT
    'CDC_DATABASE_STATE'                                AS ResultSetName,
    d.database_id                                      AS DatabaseId,
    d.name                                             AS DatabaseName,
    d.state_desc                                       AS DatabaseState,
    d.recovery_model_desc                              AS RecoveryModel,
    d.is_cdc_enabled                                   AS IsCdcEnabled,
    d.is_published                                     AS IsTransactionalOrSnapshotPublisher,
    d.log_reuse_wait_desc                              AS LogReuseWait,
    COALESCE(js.CaptureJobCount, 0)                    AS CaptureJobCount,
    COALESCE(js.CleanupJobCount, 0)                    AS CleanupJobCount,
    COALESCE(js.DisabledJobCount, 0)                   AS DisabledCdcJobCount,
    COALESCE(js.FailedJobCount, 0)                     AS FailedCdcJobCount,
    CASE
        WHEN d.is_cdc_enabled = 0 THEN 'Not enabled'
        WHEN d.is_published = 1 THEN 'Replication Log Reader Agent'
        WHEN COALESCE(js.ExistingCaptureJobs, 0) > 0 THEN 'CDC capture job'
        ELSE 'Missing or undetermined'
    END                                                AS CaptureMechanism,
    CASE WHEN d.is_cdc_enabled = 1 THEN 1 ELSE 0 END   AS flag_cdc_enabled,
    CASE
        WHEN d.is_cdc_enabled = 1
         AND d.is_published = 0
         AND COALESCE(js.ExistingCaptureJobs, 0) = 0 THEN 1 ELSE 0
    END                                                AS flag_capture_job_missing,
    CASE
        WHEN d.is_cdc_enabled = 1
         AND COALESCE(js.ExistingCleanupJobs, 0) = 0 THEN 1 ELSE 0
    END                                                AS flag_cleanup_job_missing,
    CASE WHEN COALESCE(js.DisabledJobCount, 0) > 0 THEN 1 ELSE 0 END
                                                       AS flag_cdc_job_disabled,
    CASE WHEN COALESCE(js.FailedJobCount, 0) > 0 THEN 1 ELSE 0 END
                                                       AS flag_cdc_job_failed,
    CASE WHEN d.log_reuse_wait_desc = N'REPLICATION' THEN 1 ELSE 0 END
                                                       AS flag_replication_log_holdup
FROM sys.databases AS d
LEFT JOIN #CdcJobSummary AS js
    ON js.DatabaseId = d.database_id
WHERE d.database_id > 4
ORDER BY d.is_cdc_enabled DESC, d.name;

CREATE TABLE #CdcCaptureInstances
(
    DatabaseName       SYSNAME        NOT NULL,
    CaptureInstance    SYSNAME        NOT NULL,
    SourceSchema       SYSNAME        NULL,
    SourceTable        SYSNAME        NULL,
    StartLsn           NVARCHAR(42)   NULL,
    EndLsn             NVARCHAR(42)   NULL,
    SupportsNetChanges BIT            NOT NULL,
    HasDropPending     BIT            NOT NULL,
    RoleName           SYSNAME        NULL,
    IndexName          SYSNAME        NULL,
    FilegroupName      SYSNAME        NULL,
    CreateDate         DATETIME       NOT NULL
);

CREATE TABLE #CdcCollectionErrors
(
    DatabaseName SYSNAME         NOT NULL,
    ErrorNumber  INT             NOT NULL,
    ErrorMessage NVARCHAR(4000)  NOT NULL
);

DECLARE @DatabaseName SYSNAME;
DECLARE @Sql NVARCHAR(MAX);

DECLARE cdc_database_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM sys.databases
    WHERE database_id > 4
      AND state_desc = N'ONLINE'
      AND is_cdc_enabled = 1
      AND HAS_DBACCESS(name) = 1
    ORDER BY name;

OPEN cdc_database_cursor;
FETCH NEXT FROM cdc_database_cursor INTO @DatabaseName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @Sql = N'
USE ' + QUOTENAME(@DatabaseName) + N';
INSERT #CdcCaptureInstances
(
    DatabaseName, CaptureInstance, SourceSchema, SourceTable,
    StartLsn, EndLsn, SupportsNetChanges, HasDropPending,
    RoleName, IndexName, FilegroupName, CreateDate
)
SELECT
    DB_NAME(),
    ct.capture_instance,
    OBJECT_SCHEMA_NAME(ct.source_object_id),
    OBJECT_NAME(ct.source_object_id),
    sys.fn_varbintohexstr(ct.start_lsn),
    sys.fn_varbintohexstr(ct.end_lsn),
    ct.supports_net_changes,
    ct.has_drop_pending,
    ct.role_name,
    ct.index_name,
    ct.filegroup_name,
    ct.create_date
FROM cdc.change_tables AS ct;';

    BEGIN TRY
        EXEC sys.sp_executesql @Sql;
    END TRY
    BEGIN CATCH
        INSERT #CdcCollectionErrors
            (DatabaseName, ErrorNumber, ErrorMessage)
        VALUES
            (@DatabaseName, ERROR_NUMBER(), ERROR_MESSAGE());
    END CATCH;

    FETCH NEXT FROM cdc_database_cursor INTO @DatabaseName;
END;

CLOSE cdc_database_cursor;
DEALLOCATE cdc_database_cursor;

SELECT
    'CDC_CAPTURE_INSTANCES'                    AS ResultSetName,
    DatabaseName,
    CaptureInstance,
    SourceSchema,
    SourceTable,
    StartLsn,
    EndLsn,
    SupportsNetChanges,
    HasDropPending,
    RoleName,
    IndexName,
    FilegroupName,
    CreateDate,
    CASE WHEN HasDropPending = 1 THEN 1 ELSE 0 END AS flag_drop_pending
FROM #CdcCaptureInstances
ORDER BY DatabaseName, SourceSchema, SourceTable, CaptureInstance;

IF OBJECT_ID(N'msdb.dbo.cdc_jobs') IS NOT NULL
BEGIN
    SELECT
        'CDC_AGENT_JOBS'                         AS ResultSetName,
        DB_NAME(cj.database_id)                  AS DatabaseName,
        cj.job_type                             AS JobType,
        cj.job_id                               AS JobId,
        j.name                                  AS JobName,
        j.enabled                               AS JobEnabled,
        cj.maxtrans                             AS MaxTransactions,
        cj.maxscans                             AS MaxScans,
        cj.continuous                           AS IsContinuous,
        cj.pollinginterval                      AS PollingIntervalSeconds,
        cj.retention                            AS RetentionMinutes,
        cj.threshold                            AS CleanupThreshold,
        sjs.last_run_outcome                    AS LastRunOutcome,
        CASE sjs.last_run_outcome
            WHEN 0 THEN 'Failed'
            WHEN 1 THEN 'Succeeded'
            WHEN 2 THEN 'Retry'
            WHEN 3 THEN 'Canceled'
            WHEN 4 THEN 'In progress'
            WHEN 5 THEN 'Unknown'
            ELSE 'Never run'
        END                                     AS LastRunOutcomeDescription,
        CASE
            WHEN sjs.last_run_date > 0
            THEN msdb.dbo.agent_datetime(sjs.last_run_date, sjs.last_run_time)
        END                                     AS LastRunDateTime,
        sjs.last_outcome_message                AS LastOutcomeMessage,
        CASE WHEN j.job_id IS NULL THEN 1 ELSE 0 END
                                                AS flag_job_missing,
        CASE WHEN j.job_id IS NOT NULL AND j.enabled = 0 THEN 1 ELSE 0 END
                                                AS flag_job_disabled,
        CASE WHEN sjs.last_run_outcome IN (0, 2, 3) THEN 1 ELSE 0 END
                                                AS flag_last_run_not_successful
    FROM msdb.dbo.cdc_jobs AS cj
    LEFT JOIN msdb.dbo.sysjobs AS j
        ON j.job_id = cj.job_id
    LEFT JOIN msdb.dbo.sysjobservers AS sjs
        ON sjs.job_id = cj.job_id
       AND sjs.server_id = 0
    ORDER BY DB_NAME(cj.database_id), cj.job_type;
END;

SELECT
    'CDC_COLLECTION_ERRORS' AS ResultSetName,
    DatabaseName,
    ErrorNumber,
    ErrorMessage,
    CAST(1 AS BIT) AS flag_collection_failed
FROM #CdcCollectionErrors
ORDER BY DatabaseName;

DROP TABLE #CdcCollectionErrors;
DROP TABLE #CdcCaptureInstances;
DROP TABLE #CdcJobSummary;
