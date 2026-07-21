-- ============================================================
-- Health Check: Ch 17 SQL Agent, Automation, and Alerting — 17.3 Job Ownership and Step Security
-- Checklist ref: Section 17.3
-- Min SQL version: 2016 (130)
-- Context: msdb
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- Job step security review: subsystem, proxy usage, embedded-credential
-- pattern detection, and personal-account owner flags.
-- Pattern matching on command text flags potential embedded passwords for
-- manual review only — no credential values are extracted.

USE msdb;
GO

SELECT
    j.job_id                                                        AS [job_id],
    j.name                                                          AS [job_name],
    j.enabled                                                       AS [job_enabled],
    SUSER_SNAME(j.owner_sid)                                        AS [owner_login_name],
    -- Flag owner as personal account if it doesn't match service/system patterns
    CASE
        WHEN SUSER_SNAME(j.owner_sid) IS NULL                      THEN 1   -- orphaned SID
        WHEN SUSER_SNAME(j.owner_sid) = 'sa'                       THEN 0
        WHEN SUSER_SNAME(j.owner_sid) LIKE 'NT AUTHORITY\%'        THEN 0
        WHEN SUSER_SNAME(j.owner_sid) LIKE 'NT SERVICE\%'          THEN 0
        WHEN SUSER_SNAME(j.owner_sid) LIKE '%svc%'                 THEN 0
        WHEN SUSER_SNAME(j.owner_sid) LIKE '%service%'             THEN 0
        WHEN SUSER_SNAME(j.owner_sid) LIKE '%agent%'               THEN 0
        WHEN SUSER_SNAME(j.owner_sid) LIKE '%sql%'                 THEN 0
        ELSE 1
    END                                                             AS [flag_personal_account_owner],
    -- Owner login disabled in sys.server_principals
    CASE WHEN sp.is_disabled = 1                                   THEN 1 ELSE 0 END
                                                                    AS [flag_owner_login_disabled],
    -- Step detail
    s.step_id                                                       AS [step_id],
    s.step_name                                                     AS [step_name],
    s.subsystem                                                     AS [subsystem],
    -- Proxy information (proxy_id = 0 means runs as Agent service account)
    CASE WHEN s.proxy_id > 0 THEN s.proxy_id ELSE NULL END          AS [proxy_id],
    px.name                                                         AS [proxy_name],
    px.credential_id                                                AS [proxy_credential_id],
    s.database_name                                                 AS [step_database],
    s.on_success_action                                             AS [on_success_action],
    s.on_fail_action                                                AS [on_fail_action],
    s.retry_attempts                                                AS [retry_attempts],
    s.retry_interval                                                AS [retry_interval],
    -- Flag high-risk subsystems
    CASE WHEN s.subsystem IN ('CmdExec','PowerShell','ActiveScripting','SSIS')
         THEN 1 ELSE 0 END                                          AS [flag_high_risk_subsystem],
    -- Proxy absent for high-risk subsystem (runs as Agent service account)
    CASE WHEN s.subsystem IN ('CmdExec','PowerShell','ActiveScripting','SSIS')
          AND (s.proxy_id IS NULL OR s.proxy_id = 0)
         THEN 1 ELSE 0 END                                          AS [flag_no_proxy_on_risk_subsystem],
    -- Embedded credential pattern detection (flag for review — no values extracted)
    CASE
        WHEN s.command LIKE '%password%'
          OR s.command LIKE '%passwd%'
          OR s.command LIKE '%-P %'
          OR s.command LIKE '%-P"%'
          OR s.command LIKE '%pwd=%'
          OR s.command LIKE '%pwd =%'
         THEN 1
         ELSE 0
    END                                                             AS [flag_possible_embedded_credential],
    -- Output file configured for the step
    CASE WHEN s.output_file_name IS NOT NULL
          AND s.output_file_name <> ''
         THEN 1 ELSE 0 END                                          AS [has_output_file],
    s.output_file_name                                              AS [output_file_name]
FROM msdb.dbo.sysjobs              j
INNER JOIN msdb.dbo.sysjobsteps    s   ON s.job_id     = j.job_id
LEFT  JOIN msdb.dbo.sysproxies     px  ON px.proxy_id  = s.proxy_id
LEFT  JOIN sys.server_principals   sp  ON sp.sid        = j.owner_sid
ORDER BY
    [flag_personal_account_owner]          DESC,
    [flag_possible_embedded_credential]    DESC,
    [flag_high_risk_subsystem]             DESC,
    j.name,
    s.step_id;
