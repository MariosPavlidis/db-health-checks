-- ============================================================
-- Health Check: Ch 17 SQL Agent, Automation, and Alerting — 17.4 Operators
-- Checklist ref: Section 17.4
-- Min SQL version: 2016 (130)
-- Context: msdb
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- Inventory of SQL Agent operators with pager schedules, last-contact dates,
-- fail-safe operator detection, and flags for disabled operators or operators
-- referenced in job notifications while disabled.

USE msdb;
GO

-- Retrieve the fail-safe operator ID from the Agent registry hive
DECLARE @FailsafeOpId INT = NULL;

EXEC master.dbo.xp_instance_regread
    N'HKEY_LOCAL_MACHINE',
    N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent',
    N'AlertFailSafeOperator',
    @FailsafeOpId OUTPUT;

-- Operators referenced in job on-failure notifications
;WITH NotifiedOperators AS (
    -- Alert notifications (sysnotifications has no job_id; it links alerts to operators)
    SELECT DISTINCT operator_id FROM msdb.dbo.sysnotifications
    UNION
    -- Job email/page/netsend operator references from sysjobs
    SELECT DISTINCT notify_email_operator_id
    FROM msdb.dbo.sysjobs
    WHERE notify_email_operator_id IS NOT NULL AND notify_email_operator_id > 0
    UNION
    SELECT DISTINCT notify_page_operator_id
    FROM msdb.dbo.sysjobs
    WHERE notify_page_operator_id IS NOT NULL AND notify_page_operator_id > 0
    UNION
    SELECT DISTINCT notify_netsend_operator_id
    FROM msdb.dbo.sysjobs
    WHERE notify_netsend_operator_id IS NOT NULL AND notify_netsend_operator_id > 0
)
SELECT
    op.id                                                           AS [operator_id],
    op.name                                                         AS [operator_name],
    op.enabled                                                      AS [enabled],
    op.email_address                                                AS [email_address],
    op.pager_address                                                AS [pager_address],
    op.weekday_pager_start_time                                     AS [weekday_pager_start_time],
    op.weekday_pager_end_time                                       AS [weekday_pager_end_time],
    op.saturday_pager_start_time                                    AS [saturday_pager_start_time],
    op.saturday_pager_end_time                                      AS [saturday_pager_end_time],
    op.sunday_pager_start_time                                      AS [sunday_pager_start_time],
    op.sunday_pager_end_time                                        AS [sunday_pager_end_time],
    op.pager_days                                                   AS [pager_days_bitmask],
    -- Convert last_email_date (YYYYMMDD int) to datetime
    CASE WHEN op.last_email_date = 0 THEN NULL
         ELSE msdb.dbo.agent_datetime(op.last_email_date, op.last_email_time)
    END                                                             AS [last_email_datetime],
    CASE WHEN op.last_pager_date = 0 THEN NULL
         ELSE msdb.dbo.agent_datetime(op.last_pager_date, op.last_pager_time)
    END                                                             AS [last_pager_datetime],
    CASE WHEN op.last_netsend_date = 0 THEN NULL
         ELSE msdb.dbo.agent_datetime(op.last_netsend_date, op.last_netsend_time)
    END                                                             AS [last_netsend_datetime],
    -- Fail-safe designation
    CASE WHEN op.id = @FailsafeOpId                                THEN 1 ELSE 0 END
                                                                    AS [is_failsafe_operator],
    -- Referenced by any job notification
    CASE WHEN no2.operator_id IS NOT NULL                          THEN 1 ELSE 0 END
                                                                    AS [is_referenced_in_notifications],
    -- ── Risk flags ──────────────────────────────────────────
    CASE WHEN op.enabled = 0                                       THEN 1 ELSE 0 END
                                                                    AS [flag_operator_disabled],
    CASE WHEN (op.email_address IS NULL OR op.email_address = '')  THEN 1 ELSE 0 END
                                                                    AS [flag_no_email_address],
    -- Disabled but still referenced in job notifications
    CASE WHEN op.enabled = 0
          AND no2.operator_id IS NOT NULL                          THEN 1 ELSE 0 END
                                                                    AS [flag_disabled_but_referenced],
    -- Fail-safe operator is disabled
    CASE WHEN op.id = @FailsafeOpId
          AND op.enabled = 0                                       THEN 1 ELSE 0 END
                                                                    AS [flag_failsafe_operator_disabled]
FROM msdb.dbo.sysoperators                  op
LEFT JOIN NotifiedOperators                 no2  ON no2.operator_id = op.id
ORDER BY
    [flag_disabled_but_referenced] DESC,
    [flag_failsafe_operator_disabled] DESC,
    [flag_operator_disabled]        DESC,
    [flag_no_email_address]         DESC,
    op.name;
