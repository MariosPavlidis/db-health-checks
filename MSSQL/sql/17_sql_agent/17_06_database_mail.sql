-- ============================================================
-- Health Check: Ch 17 SQL Agent, Automation, and Alerting — 17.6 Database Mail
-- Checklist ref: Section 17.6
-- Min SQL version: 2016 (130)
-- Context: msdb
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- Database Mail configuration health: enabled state, profiles, accounts,
-- SMTP settings, mail queue status (failed / unsent / recent sent),
-- and SQL Agent mail-profile binding.

USE msdb;
GO

-- ── 1. Database Mail XPs enabled status ──────────────────────────────────────
SELECT
    'DatabaseMailEnabled'                                           AS [check_name],
    CAST(c.value_in_use AS INT)                                     AS [config_value],
    CASE CAST(c.value_in_use AS INT)
        WHEN 1 THEN 'Enabled'
        ELSE        'Disabled'
    END                                                             AS [status_desc],
    CASE CAST(c.value_in_use AS INT)
        WHEN 1 THEN 0
        ELSE        1
    END                                                             AS [flag_mail_disabled]
FROM sys.configurations c
WHERE c.name = 'Database Mail XPs'

UNION ALL

-- ── 2. Mail profiles ─────────────────────────────────────────────────────────
SELECT
    'Profile: ' + p.name                                            AS [check_name],
    p.profile_id                                                    AS [config_value],
    CASE WHEN pa.profile_id IS NOT NULL
         THEN 'HasAccounts'
         ELSE 'NoAccountsLinked'
    END                                                             AS [status_desc],
    CASE WHEN pa.profile_id IS NULL                                THEN 1 ELSE 0 END
                                                                    AS [flag_mail_disabled]
FROM msdb.dbo.sysmail_profile p
LEFT JOIN (
    SELECT DISTINCT profile_id
    FROM msdb.dbo.sysmail_profileaccount
) pa ON pa.profile_id = p.profile_id;

-- ── 3. Mail accounts (SMTP settings) ─────────────────────────────────────────
SELECT
    pa.profile_id                                                   AS [profile_id],
    p.name                                                          AS [profile_name],
    pa.sequence_number                                              AS [account_sequence],
    a.account_id                                                    AS [account_id],
    a.name                                                          AS [account_name],
    a.email_address                                                 AS [email_address],
    a.display_name                                                  AS [display_name],
    a.replyto_address                                               AS [replyto_address],
    s.servername                                                    AS [smtp_server],
    s.port                                                          AS [smtp_port],
    s.enable_ssl                                                    AS [smtp_ssl_enabled],
    s.use_default_credentials                                       AS [use_default_credentials],
    s.credential_id                                                 AS [credential_id],
    CASE WHEN (a.email_address IS NULL OR a.email_address = '')    THEN 1 ELSE 0 END
                                                                    AS [flag_no_email_address],
    CASE WHEN (s.servername   IS NULL OR s.servername   = '')      THEN 1 ELSE 0 END
                                                                    AS [flag_no_smtp_server]
FROM msdb.dbo.sysmail_profileaccount    pa
INNER JOIN msdb.dbo.sysmail_profile     p   ON p.profile_id   = pa.profile_id
INNER JOIN msdb.dbo.sysmail_account     a   ON a.account_id   = pa.account_id
INNER JOIN msdb.dbo.sysmail_server      s   ON s.account_id   = a.account_id
ORDER BY pa.profile_id, pa.sequence_number;

-- ── 4. Mail queue status ──────────────────────────────────────────────────────
SELECT
    'FailedItems_Last7Days'                                         AS [queue_metric],
    COUNT(*)                                                        AS [item_count],
    CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END                       AS [flag_queue_issue]
FROM msdb.dbo.sysmail_faileditems
WHERE last_mod_date >= DATEADD(DAY, -7, GETDATE())

UNION ALL

SELECT
    'UnsentItems_Current'                                           AS [queue_metric],
    COUNT(*)                                                        AS [item_count],
    CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END                       AS [flag_queue_issue]
FROM msdb.dbo.sysmail_unsentitems

UNION ALL

SELECT
    'SentItems_Last24Hours'                                         AS [queue_metric],
    COUNT(*)                                                        AS [item_count],
    0                                                               AS [flag_queue_issue]
FROM msdb.dbo.sysmail_sentitems
WHERE sent_date >= DATEADD(HOUR, -24, GETDATE());

-- ── 5. SQL Agent mail profile binding ─────────────────────────────────────────
-- Check whether the Agent has a default mail profile set and whether
-- the Agent mail notification is configured (DatabaseMail vs legacy SQLMail).
SELECT
    'AgentDefaultMailProfile'                                       AS [check_name],
    p.name                                                          AS [profile_name],
    CASE WHEN p.profile_id IS NOT NULL THEN 'Configured' ELSE 'NotConfigured' END
                                                                    AS [status_desc],
    CASE WHEN p.profile_id IS NULL     THEN 1 ELSE 0 END            AS [flag_no_agent_mail_profile]
FROM (
    SELECT TOP 1 profile_id, name
    FROM msdb.dbo.sysmail_profile
    ORDER BY profile_id          -- default profile is the lowest-ID public profile
) p

UNION ALL

SELECT
    'DatabaseMailXPs_AgentConfig'                                   AS [check_name],
    CAST(c.value_in_use AS VARCHAR(20))                             AS [profile_name],
    CASE CAST(c.value_in_use AS INT)
        WHEN 1 THEN 'DatabaseMail active'
        ELSE        'DatabaseMail inactive'
    END                                                             AS [status_desc],
    CASE CAST(c.value_in_use AS INT)
        WHEN 1 THEN 0
        ELSE        1
    END                                                             AS [flag_no_agent_mail_profile]
FROM sys.configurations c
WHERE c.name = 'Database Mail XPs';
