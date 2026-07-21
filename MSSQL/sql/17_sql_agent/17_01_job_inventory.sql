-- ============================================================
-- Health Check: Ch 17 SQL Agent, Automation, and Alerting — 17.1 Job Inventory
-- Checklist ref: Section 17.1
-- Min SQL version: 2016 (130)
-- Context: msdb
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- Full inventory of SQL Agent jobs with schedule counts, last-run status,
-- next-run date, and risk flags: orphaned owners, never-run, enabled with
-- no schedule, disabled with an active schedule.

USE msdb;
GO

;WITH JobStepCounts AS (
    SELECT
        job_id,
        COUNT(*)                            AS step_count,
        MAX(CASE WHEN output_file_name <> '' AND output_file_name IS NOT NULL
                 THEN 1 ELSE 0 END)        AS has_output_file
    FROM msdb.dbo.sysjobsteps
    GROUP BY job_id
),
JobScheduleCounts AS (
    SELECT
        jsch.job_id,
        COUNT(*)                            AS schedule_count
    FROM msdb.dbo.sysjobschedules  jsch
    INNER JOIN msdb.dbo.sysschedules sch
        ON sch.schedule_id = jsch.schedule_id
    WHERE sch.enabled = 1
    GROUP BY jsch.job_id
),
NextRun AS (
    -- Earliest next_run_date across all active schedules for the job
    SELECT
        jsch.job_id,
        MIN(
            CASE WHEN jsch.next_run_date = 0 THEN NULL
                 ELSE msdb.dbo.agent_datetime(jsch.next_run_date, jsch.next_run_time)
            END
        )                                   AS next_run_datetime
    FROM msdb.dbo.sysjobschedules  jsch
    INNER JOIN msdb.dbo.sysschedules sch
        ON sch.schedule_id = jsch.schedule_id
    WHERE sch.enabled = 1
    GROUP BY jsch.job_id
),
LastRunHistory AS (
    -- Most recent job-level history record per job (step_id = 0)
    SELECT
        instance_id,
        job_id,
        run_date,
        run_time,
        run_status,
        run_duration,
        retries_attempted,
        ROW_NUMBER() OVER (PARTITION BY job_id ORDER BY run_date DESC, run_time DESC) AS rn
    FROM msdb.dbo.sysjobhistory
    WHERE step_id = 0
)
SELECT
    j.job_id                                                        AS [job_id],
    j.name                                                          AS [job_name],
    j.enabled                                                       AS [enabled],
    j.description                                                   AS [description],
    cat.name                                                        AS [category_name],
    j.owner_sid,
    SUSER_SNAME(j.owner_sid)                                        AS [owner_login_name],
    CONVERT(datetime, CAST(j.date_created AS CHAR(8)), 112)         AS [date_created],
    CONVERT(datetime, CAST(j.date_modified AS CHAR(8)), 112)        AS [date_modified],
    ISNULL(sc.step_count,     0)                                    AS [step_count],
    ISNULL(jsc.schedule_count,0)                                    AS [schedule_count],
    ISNULL(lrh.run_date,      0)                                    AS [last_run_date],
    ISNULL(lrh.run_time,      0)                                    AS [last_run_time],
    -- Convert run_date / run_time to a readable datetime
    CASE WHEN ISNULL(lrh.run_date, 0) = 0 THEN NULL
         ELSE msdb.dbo.agent_datetime(lrh.run_date, lrh.run_time)
    END                                                             AS [last_run_datetime],
    lrh.run_status                                                  AS [last_run_status],
    -- 0=Failed 1=Succeeded 2=Retry 3=Canceled 5=Unknown
    CASE lrh.run_status
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Canceled'
        WHEN 5 THEN 'Unknown'
        ELSE        'Unknown'
    END                                                             AS [last_run_status_desc],
    -- Duration stored as HHMMSS integer; convert to seconds
    CASE WHEN lrh.run_duration IS NULL THEN NULL
         ELSE (lrh.run_duration / 10000) * 3600
            + ((lrh.run_duration % 10000) / 100) * 60
            + (lrh.run_duration % 100)
    END                                                             AS [last_run_duration_sec],
    nr.next_run_datetime                                            AS [next_run_datetime],
    j.notify_level_email                                            AS [notify_level_email],
    j.notify_level_page                                             AS [notify_level_page],
    j.notify_level_netsend                                          AS [notify_level_netsend],
    j.delete_level                                                  AS [delete_level],
    ISNULL(sc.has_output_file, 0)                                   AS [has_output_file],
    -- ── Risk flags ──────────────────────────────────────────
    CASE WHEN ISNULL(jsc.schedule_count, 0) = 0                THEN 1 ELSE 0 END
                                                                    AS [flag_has_no_schedule],
    CASE WHEN ISNULL(lrh.run_date, 0) = 0                      THEN 1 ELSE 0 END
                                                                    AS [flag_never_run],
    CASE WHEN j.enabled = 1
          AND ISNULL(lrh.run_date, 0) = 0                      THEN 1 ELSE 0 END
                                                                    AS [flag_enabled_never_run],
    CASE WHEN j.enabled = 0
          AND ISNULL(jsc.schedule_count, 0) > 0                THEN 1 ELSE 0 END
                                                                    AS [flag_disabled_with_active_schedule],
    -- Owner is a personal account if login does not match common service-account patterns
    CASE
        WHEN SUSER_SNAME(j.owner_sid) IS NULL                  THEN 1   -- orphaned SID
        WHEN SUSER_SNAME(j.owner_sid) = 'sa'                   THEN 0
        WHEN SUSER_SNAME(j.owner_sid) LIKE 'NT AUTHORITY\%'    THEN 0
        WHEN SUSER_SNAME(j.owner_sid) LIKE 'NT SERVICE\%'      THEN 0
        WHEN SUSER_SNAME(j.owner_sid) LIKE '%svc%'             THEN 0
        WHEN SUSER_SNAME(j.owner_sid) LIKE '%service%'         THEN 0
        WHEN SUSER_SNAME(j.owner_sid) LIKE '%agent%'           THEN 0
        WHEN SUSER_SNAME(j.owner_sid) LIKE '%sql%'             THEN 0
        ELSE 1
    END                                                             AS [flag_personal_account_owner],
    -- Flag if the job-owner login is disabled in sys.server_principals
    CASE WHEN sp.is_disabled = 1                               THEN 1 ELSE 0 END
                                                                    AS [flag_owner_login_disabled]
FROM msdb.dbo.sysjobs             j
INNER JOIN msdb.dbo.syscategories cat
    ON cat.category_id = j.category_id
LEFT JOIN JobStepCounts           sc
    ON sc.job_id = j.job_id
LEFT JOIN JobScheduleCounts       jsc
    ON jsc.job_id = j.job_id
LEFT JOIN NextRun                 nr
    ON nr.job_id = j.job_id
LEFT JOIN LastRunHistory          lrh
    ON lrh.job_id = j.job_id AND lrh.rn = 1
LEFT JOIN sys.server_principals   sp
    ON sp.sid = j.owner_sid
ORDER BY
    j.enabled DESC,
    [flag_personal_account_owner] DESC,
    [flag_never_run] DESC,
    j.name;
