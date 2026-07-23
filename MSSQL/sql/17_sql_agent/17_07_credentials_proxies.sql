-- ============================================================
-- Health Check: Ch 17 SQL Agent — 17.7 Credentials and Agent Proxies
-- Checklist ref: Section 17.7
-- Min SQL version: 2016 (130)
-- ============================================================
-- Query 1: Server-level credentials — name, identity, creation date, and
--           whether they are referenced by any proxy.
--           Unused credentials that hold Windows identities can be privilege risks.
-- Query 2: SQL Agent proxies — name, credential, enabled state, and the
--           Windows identity they impersonate.
-- Query 3: Proxy-to-subsystem mappings — which subsystems each proxy can access.
--           Flags proxies granted to high-risk subsystems (CmdExec, PowerShell,
--           ActiveX, SSIS) that allow OS-level command execution.
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- ── 1. Server credentials ─────────────────────────────────────────────────────
SELECT
    c.name                                          AS CredentialName,
    c.credential_id,
    c.credential_identity                           AS WindowsIdentity,
    c.create_date                                   AS CreateDate,
    c.modify_date                                   AS ModifyDate,
    c.target_type                                   AS TargetType,
    c.target_id                                     AS TargetId,
    -- Is this credential referenced by any proxy?
    CASE WHEN EXISTS (
        SELECT 1 FROM msdb.dbo.sysproxies p
        WHERE p.credential_id = c.credential_id
    ) THEN 1 ELSE 0 END                             AS IsUsedByProxy,
    CASE WHEN NOT EXISTS (
        SELECT 1 FROM msdb.dbo.sysproxies p
        WHERE p.credential_id = c.credential_id
    ) THEN 'UNUSED_CREDENTIAL' ELSE '' END          AS CredentialFlag
FROM sys.credentials c
ORDER BY c.name;

-- ── 2. SQL Agent proxies ──────────────────────────────────────────────────────
SELECT
    p.proxy_id,
    p.name                                          AS ProxyName,
    p.credential_id,
    c.name                                          AS CredentialName,
    c.credential_identity                           AS WindowsIdentity,
    p.enabled                                       AS IsEnabled,
    p.description,
    p.flags,
    CASE WHEN p.enabled = 0 THEN 'PROXY_DISABLED' ELSE '' END
                                                    AS ProxyFlag
FROM msdb.dbo.sysproxies p
JOIN sys.credentials c
    ON c.credential_id = p.credential_id
ORDER BY p.name;

-- ── 3. Proxy-to-subsystem mappings ───────────────────────────────────────────
SELECT
    p.name                                          AS ProxyName,
    c.credential_identity                           AS WindowsIdentity,
    p.enabled                                       AS ProxyEnabled,
    ss.subsystem_id,
    ss.subsystem                                    AS SubsystemName,
    ss.description                                  AS SubsystemDesc,
    -- Flag subsystems that allow OS-level execution
    CASE
        WHEN ss.subsystem IN ('CmdExec', 'PowerShell', 'ActiveScripting')
             THEN 'HIGH_RISK_SUBSYSTEM'
        WHEN ss.subsystem = 'SSIS'
             THEN 'ELEVATED_SUBSYSTEM'
        ELSE ''
    END                                             AS SubsystemRiskFlag
FROM msdb.dbo.sysproxies p
JOIN sys.credentials c
    ON c.credential_id = p.credential_id
JOIN msdb.dbo.sysproxysubsystem pss
    ON pss.proxy_id = p.proxy_id
JOIN msdb.dbo.syssubsystems ss
    ON ss.subsystem_id = pss.subsystem_id
ORDER BY SubsystemRiskFlag DESC, p.name, ss.subsystem;
