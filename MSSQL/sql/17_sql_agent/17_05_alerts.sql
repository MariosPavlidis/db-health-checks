-- ============================================================
-- Health Check: Ch 17 SQL Agent, Automation, and Alerting — 17.5 Alerts and Coverage
-- Checklist ref: Section 17.5
-- Min SQL version: 2016 (130)
-- Context: msdb
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- Inventory of SQL Agent alerts with operator notifications, plus a coverage
-- gap analysis showing which critical severity levels (19-25) and critical
-- error numbers (823, 824, 825, 9002) have no alert defined.

USE msdb;
GO

-- ── Section A: Alert inventory ────────────────────────────────────────────────
SELECT
    a.id                                                            AS [alert_id],
    a.name                                                          AS [alert_name],
    a.enabled                                                       AS [enabled],
    a.event_source                                                  AS [event_source],
    a.message_id                                                    AS [message_id],
    a.severity                                                      AS [severity],
    a.delay_between_responses                                       AS [delay_between_responses_sec],
    -- Convert last_occurrence_date (YYYYMMDD int)
    CASE WHEN a.last_occurrence_date = 0 THEN NULL
         ELSE msdb.dbo.agent_datetime(a.last_occurrence_date, a.last_occurrence_time)
    END                                                             AS [last_occurrence_datetime],
    CASE WHEN a.last_response_date = 0 THEN NULL
         ELSE msdb.dbo.agent_datetime(a.last_response_date, a.last_response_time)
    END                                                             AS [last_response_datetime],
    a.occurrence_count                                              AS [occurrence_count],
    a.job_id                                                        AS [response_job_id],
    a.performance_condition                                         AS [performance_condition],
    op.name                                                         AS [notification_operator],
    n.notification_method                                           AS [notification_method],
    -- Notification method decode (bitmask: 1=email, 2=pager, 4=netsend)
    CASE WHEN n.notification_method & 1 > 0 THEN 'Email '   ELSE '' END
  + CASE WHEN n.notification_method & 2 > 0 THEN 'Pager '  ELSE '' END
  + CASE WHEN n.notification_method & 4 > 0 THEN 'NetSend' ELSE '' END
                                                                    AS [notification_method_desc],
    -- ── Risk flags ──────────────────────────────────────────
    CASE WHEN a.enabled = 0                                        THEN 1 ELSE 0 END
                                                                    AS [flag_alert_disabled],
    CASE WHEN op.name IS NULL AND a.job_id IS NULL                 THEN 1 ELSE 0 END
                                                                    AS [flag_no_response_configured],
    CASE WHEN a.severity BETWEEN 19 AND 25                         THEN 1 ELSE 0 END
                                                                    AS [flag_critical_severity_alert],
    CASE WHEN a.message_id IN (823, 824, 825, 9002)               THEN 1 ELSE 0 END
                                                                    AS [flag_critical_error_alert]
FROM msdb.dbo.sysalerts                 a
LEFT JOIN msdb.dbo.sysnotifications     n   ON n.alert_id    = a.id
LEFT JOIN msdb.dbo.sysoperators         op  ON op.id         = n.operator_id

UNION ALL

-- ── Section B: Coverage gap analysis ──────────────────────────────────────────
-- Emit a row per critical severity / error number that lacks an enabled alert.
-- These rows have alert_id = NULL to distinguish them from real alert rows.
SELECT
    NULL                                                            AS [alert_id],
    'COVERAGE GAP — Severity ' + CAST(sv.severity AS VARCHAR(3))   AS [alert_name],
    0                                                               AS [enabled],
    'SQL Server Event'                                              AS [event_source],
    NULL                                                            AS [message_id],
    sv.severity                                                     AS [severity],
    NULL, NULL, NULL, NULL, NULL, NULL,
    NULL                                                            AS [notification_operator],
    NULL                                                            AS [notification_method],
    NULL                                                            AS [notification_method_desc],
    0                                                               AS [flag_alert_disabled],
    0                                                               AS [flag_no_response_configured],
    1                                                               AS [flag_critical_severity_alert],
    0                                                               AS [flag_critical_error_alert]
FROM (VALUES (19),(20),(21),(22),(23),(24),(25)) AS sv(severity)
WHERE NOT EXISTS (
    SELECT 1
    FROM msdb.dbo.sysalerts a
    WHERE a.severity = sv.severity
      AND a.enabled  = 1
      AND a.message_id = 0   -- severity-level alert has message_id = 0
)

UNION ALL

SELECT
    NULL                                                            AS [alert_id],
    'COVERAGE GAP — Error ' + CAST(en.err AS VARCHAR(10))          AS [alert_name],
    0                                                               AS [enabled],
    'SQL Server Event'                                              AS [event_source],
    en.err                                                          AS [message_id],
    NULL                                                            AS [severity],
    NULL, NULL, NULL, NULL, NULL, NULL,
    NULL                                                            AS [notification_operator],
    NULL                                                            AS [notification_method],
    NULL                                                            AS [notification_method_desc],
    0                                                               AS [flag_alert_disabled],
    0                                                               AS [flag_no_response_configured],
    0                                                               AS [flag_critical_severity_alert],
    1                                                               AS [flag_critical_error_alert]
FROM (VALUES (823),(824),(825),(9002)) AS en(err)
WHERE NOT EXISTS (
    SELECT 1
    FROM msdb.dbo.sysalerts a
    WHERE a.message_id = en.err
      AND a.enabled    = 1
)

ORDER BY
    [flag_critical_severity_alert]  DESC,
    [flag_critical_error_alert]     DESC,
    [severity]                      DESC,
    [message_id],
    [alert_name];
