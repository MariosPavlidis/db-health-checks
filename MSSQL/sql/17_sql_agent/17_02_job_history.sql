-- ============================================================
-- Health Check: Ch 17 SQL Agent, Automation, and Alerting — 17.2 Job History Analysis
-- Checklist ref: Section 17.2
-- Min SQL version: 2016 (130)
-- Context: msdb
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- Per-job run statistics over the last 90 days: success/failure counts,
-- duration stats, failure-ratio, duration regression, silent step failures,
-- and missing notification-on-failure configuration.

USE msdb;
GO

;WITH HistoryWindow AS (
    -- Job-level records (step_id = 0) within last 90 days
    SELECT
        h.job_id,
        h.run_date,
        h.run_time,
        h.run_status,
        h.run_duration,
        -- Convert msdb YYYYMMDD + HHMMSS integers to datetime
        msdb.dbo.agent_datetime(h.run_date, h.run_time) AS run_datetime,
        -- Duration in seconds
        (h.run_duration / 10000) * 3600
        + ((h.run_duration % 10000) / 100) * 60
        + (h.run_duration % 100)            AS duration_sec
    FROM msdb.dbo.sysjobhistory h
    WHERE h.step_id = 0
      AND h.run_date >= CAST(
              CONVERT(varchar(8), DATEADD(DAY, -90, GETDATE()), 112)
              AS int)
),
LastRun AS (
    SELECT job_id, MAX(run_datetime) AS max_run_datetime
    FROM HistoryWindow
    GROUP BY job_id
),
JobStats AS (
    SELECT
        hw.job_id,
        COUNT(*)                                                    AS total_runs,
        SUM(CASE WHEN run_status = 1 THEN 1 ELSE 0 END)            AS successful_runs,
        SUM(CASE WHEN run_status = 0 THEN 1 ELSE 0 END)            AS failed_runs,
        SUM(CASE WHEN run_status = 2 THEN 1 ELSE 0 END)            AS retry_runs,
        SUM(CASE WHEN run_status = 3 THEN 1 ELSE 0 END)            AS canceled_runs,
        CAST(
            100.0 * SUM(CASE WHEN run_status = 0 THEN 1 ELSE 0 END)
            / NULLIF(COUNT(*), 0)
            AS DECIMAL(5,2))                                        AS failure_ratio_pct,
        AVG(CAST(duration_sec AS BIGINT))                           AS avg_duration_sec,
        MAX(duration_sec)                                           AS max_duration_sec,
        MIN(duration_sec)                                           AS min_duration_sec,
        MAX(run_datetime)                                           AS last_run_datetime,
        -- Last run status by picking the most recent record
        MAX(CASE WHEN hw.run_datetime = lr.max_run_datetime
             THEN hw.run_status ELSE NULL END)                      AS last_run_status
    FROM HistoryWindow hw
    JOIN LastRun lr ON lr.job_id = hw.job_id
    GROUP BY hw.job_id
),
-- Step-level failures where the parent job-level record shows success (silent failures)
StepFailuresInSuccessfulJobs AS (
    SELECT DISTINCT
        hs.job_id
    FROM msdb.dbo.sysjobhistory hs
    WHERE hs.step_id > 0
      AND hs.run_status = 0
      AND hs.run_date >= CAST(
              CONVERT(varchar(8), DATEADD(DAY, -90, GETDATE()), 112)
              AS int)
      AND EXISTS (
          SELECT 1
          FROM msdb.dbo.sysjobhistory hjob
          WHERE hjob.job_id    = hs.job_id
            AND hjob.step_id   = 0
            AND hjob.run_status = 1
            AND hjob.run_date  = hs.run_date
      )
)
SELECT
    j.job_id                                                        AS [job_id],
    j.name                                                          AS [job_name],
    j.enabled                                                       AS [enabled],
    SUSER_SNAME(j.owner_sid)                                        AS [owner_login_name],
    -- 90-day run statistics
    ISNULL(js.total_runs,       0)                                  AS [total_runs_90d],
    ISNULL(js.successful_runs,  0)                                  AS [successful_runs_90d],
    ISNULL(js.failed_runs,      0)                                  AS [failed_runs_90d],
    ISNULL(js.retry_runs,       0)                                  AS [retry_runs_90d],
    ISNULL(js.canceled_runs,    0)                                  AS [canceled_runs_90d],
    ISNULL(js.failure_ratio_pct,0)                                  AS [failure_ratio_pct],
    js.avg_duration_sec                                             AS [avg_duration_sec],
    js.max_duration_sec                                             AS [max_duration_sec],
    js.min_duration_sec                                             AS [min_duration_sec],
    js.last_run_datetime                                            AS [last_run_datetime],
    js.last_run_status                                              AS [last_run_status],
    CASE js.last_run_status
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Canceled'
        WHEN 5 THEN 'Unknown'
        ELSE        'No history'
    END                                                             AS [last_run_status_desc],
    -- Notification configuration
    j.notify_level_email                                            AS [notify_level_email],
    j.notify_level_page                                             AS [notify_level_page],
    j.notify_level_netsend                                          AS [notify_level_netsend],
    -- ── Risk flags ──────────────────────────────────────────
    CASE WHEN ISNULL(js.successful_runs, 0) = 0
          AND ISNULL(js.total_runs, 0) > 0                         THEN 1 ELSE 0 END
                                                                    AS [flag_no_successful_runs],
    CASE WHEN ISNULL(js.failure_ratio_pct, 0) > 20                 THEN 1 ELSE 0 END
                                                                    AS [flag_high_failure_ratio],
    CASE WHEN ISNULL(js.last_run_status, -1) = 0                   THEN 1 ELSE 0 END
                                                                    AS [flag_last_run_failed],
    -- Duration regression: max > 3x avg
    CASE WHEN js.max_duration_sec > js.avg_duration_sec * 3        THEN 1 ELSE 0 END
                                                                    AS [flag_duration_regression],
    -- Silent step failure: step failed but job-level shows success
    CASE WHEN sf.job_id IS NOT NULL                                THEN 1 ELSE 0 END
                                                                    AS [flag_silent_step_failure],
    -- No failure notification configured at all
    CASE
        WHEN (j.notify_level_email   = 0
          AND j.notify_level_page    = 0
          AND j.notify_level_netsend = 0)                           THEN 1 ELSE 0 END
                                                                    AS [flag_no_failure_notification],
    -- Jobs that exist but have zero history in window
    CASE WHEN js.job_id IS NULL                                    THEN 1 ELSE 0 END
                                                                    AS [flag_no_history_in_90d]
FROM msdb.dbo.sysjobs                        j
LEFT JOIN JobStats                           js  ON js.job_id  = j.job_id
LEFT JOIN StepFailuresInSuccessfulJobs       sf  ON sf.job_id  = j.job_id
ORDER BY
    [flag_last_run_failed]        DESC,
    [flag_high_failure_ratio]     DESC,
    [flag_no_failure_notification]DESC,
    [flag_duration_regression]    DESC,
    j.name;
