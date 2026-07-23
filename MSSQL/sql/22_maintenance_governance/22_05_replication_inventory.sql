-- =============================================================================
-- Health Check: Ch 22 Maintenance and Operational Governance — 22.5 Replication
-- Checklist ref: Section 22.5
-- Min SQL version: SQL Server 2016
--
-- Detects replication database roles and SQL Agent jobs. The is_subscribed
-- column is intentionally not used because Microsoft documents that it always
-- returns 0 and does not report subscriber status.
-- =============================================================================
SET NOCOUNT ON;

IF TRY_CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT
        'VERSION_GUARD' AS ResultSetName,
        'Requires SQL Server 2016 or later.' AS Note;
    RETURN;
END;

;WITH ReplicationAgentSteps AS
(
    SELECT
        s.job_id,
        MAX(CASE UPPER(s.subsystem)
            WHEN N'SNAPSHOT'     THEN N'Snapshot Agent'
            WHEN N'LOGREADER'    THEN N'Log Reader Agent'
            WHEN N'DISTRIBUTION' THEN N'Distribution Agent'
            WHEN N'MERGE'        THEN N'Merge Agent'
            WHEN N'QUEUEREADER'  THEN N'Queue Reader Agent'
        END) AS AgentType,
        COUNT(*) AS ReplicationStepCount
    FROM msdb.dbo.sysjobsteps AS s
    WHERE UPPER(s.subsystem) IN
        (N'SNAPSHOT', N'LOGREADER', N'DISTRIBUTION', N'MERGE', N'QUEUEREADER')
    GROUP BY s.job_id
),
ReplicationJobSummary AS
(
    SELECT
        COUNT(*) AS ReplicationAgentJobCount,
        SUM(CASE WHEN j.enabled = 0 THEN 1 ELSE 0 END) AS DisabledReplicationJobCount,
        SUM(CASE WHEN sjs.last_run_outcome IN (0, 2, 3) THEN 1 ELSE 0 END)
            AS FailedReplicationJobCount
    FROM ReplicationAgentSteps AS ras
    JOIN msdb.dbo.sysjobs AS j
        ON j.job_id = ras.job_id
    LEFT JOIN msdb.dbo.sysjobservers AS sjs
        ON sjs.job_id = j.job_id
       AND sjs.server_id = 0
)
SELECT
    'REPLICATION_DATABASE_STATE'                         AS ResultSetName,
    d.database_id                                       AS DatabaseId,
    d.name                                              AS DatabaseName,
    d.state_desc                                        AS DatabaseState,
    d.recovery_model_desc                               AS RecoveryModel,
    d.is_published                                      AS IsTransactionalOrSnapshotPublisher,
    d.is_merge_published                                AS IsMergePublisher,
    d.is_distributor                                    AS IsDistributionDatabase,
    d.is_sync_with_backup                               AS IsSyncWithBackup,
    d.log_reuse_wait_desc                               AS LogReuseWait,
    rjs.ReplicationAgentJobCount,
    rjs.DisabledReplicationJobCount,
    rjs.FailedReplicationJobCount,
    CASE
        WHEN d.is_published = 1
          OR d.is_merge_published = 1
          OR d.is_distributor = 1 THEN 1 ELSE 0
    END                                                 AS flag_replication_configured,
    CASE WHEN d.log_reuse_wait_desc = N'REPLICATION' THEN 1 ELSE 0 END
                                                        AS flag_replication_log_holdup
FROM sys.databases AS d
CROSS JOIN ReplicationJobSummary AS rjs
WHERE d.database_id > 4
   OR d.is_distributor = 1
ORDER BY
    CASE
        WHEN d.is_published = 1
          OR d.is_merge_published = 1
          OR d.is_distributor = 1 THEN 0 ELSE 1
    END,
    d.name;

;WITH ReplicationAgentSteps AS
(
    SELECT
        s.job_id,
        MAX(CASE UPPER(s.subsystem)
            WHEN N'SNAPSHOT'     THEN N'Snapshot Agent'
            WHEN N'LOGREADER'    THEN N'Log Reader Agent'
            WHEN N'DISTRIBUTION' THEN N'Distribution Agent'
            WHEN N'MERGE'        THEN N'Merge Agent'
            WHEN N'QUEUEREADER'  THEN N'Queue Reader Agent'
        END) AS AgentType,
        COUNT(*) AS ReplicationStepCount
    FROM msdb.dbo.sysjobsteps AS s
    WHERE UPPER(s.subsystem) IN
        (N'SNAPSHOT', N'LOGREADER', N'DISTRIBUTION', N'MERGE', N'QUEUEREADER')
    GROUP BY s.job_id
)
SELECT
    'REPLICATION_AGENT_JOBS'                       AS ResultSetName,
    j.job_id                                      AS JobId,
    j.name                                        AS JobName,
    ras.AgentType,
    ras.ReplicationStepCount,
    j.enabled                                     AS JobEnabled,
    SUSER_SNAME(j.owner_sid)                      AS JobOwner,
    sjs.last_run_outcome                          AS LastRunOutcome,
    CASE sjs.last_run_outcome
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Canceled'
        WHEN 4 THEN 'In progress'
        WHEN 5 THEN 'Unknown'
        ELSE 'Never run'
    END                                           AS LastRunOutcomeDescription,
    CASE
        WHEN sjs.last_run_date > 0
        THEN msdb.dbo.agent_datetime(sjs.last_run_date, sjs.last_run_time)
    END                                           AS LastRunDateTime,
    sjs.last_outcome_message                      AS LastOutcomeMessage,
    j.date_created                                AS DateCreated,
    j.date_modified                               AS DateModified,
    CASE WHEN j.enabled = 0 THEN 1 ELSE 0 END     AS flag_agent_job_disabled,
    CASE WHEN sjs.last_run_outcome IN (0, 2, 3) THEN 1 ELSE 0 END
                                                  AS flag_last_run_not_successful
FROM ReplicationAgentSteps AS ras
JOIN msdb.dbo.sysjobs AS j
    ON j.job_id = ras.job_id
LEFT JOIN msdb.dbo.sysjobservers AS sjs
    ON sjs.job_id = j.job_id
   AND sjs.server_id = 0
ORDER BY ras.AgentType, j.name;
