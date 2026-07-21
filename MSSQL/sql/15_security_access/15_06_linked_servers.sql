-- ============================================================
-- Health Check: Ch 15 Security and Access — 15.6 Linked Servers and Credentials
-- Checklist ref: Section 15.6
-- Min SQL version: 2016 (130)
-- ============================================================
-- Part 1: Linked server definitions with security mapping details.
--         A public (local_principal_id = 0) mapping means ALL logins on this
--         instance can connect to the remote server — flagged as PUBLIC_MAPPING_RISK.
-- Part 2: SQL Server credentials (used by Agent proxies, linked server auth, etc.)
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- ── Part 1: Linked servers and their login mappings ───────────────────────────
SELECT
    ls.server_id                                            AS LinkedServerId,
    ls.name                                                 AS LinkedServerName,
    ls.product                                              AS Product,
    ls.provider                                             AS Provider,
    ls.data_source                                          AS DataSource,
    ls.is_rpc_out_enabled                                   AS RPCOutEnabled,
    ls.is_data_access_enabled                               AS DataAccessEnabled,
    ls.is_distributor                                       AS IsDistributor,
    ls.is_publisher                                         AS IsPublisher,
    ls.is_subscriber                                        AS IsSubscriber,
    ls.is_remote_login_enabled                              AS RemoteLoginEnabled,
    -- Security mapping detail
    lsl.local_principal_id                                  AS LocalPrincipalId,
    CASE
        WHEN lsl.local_principal_id = 0
        THEN 'All unmapped logins (public)'
        ELSE SUSER_SNAME(sp.sid)
    END                                                     AS LocalLoginName,
    lsl.remote_name                                         AS RemoteLoginName,
    lsl.uses_self_credential                                AS UsesSelfCredential,
    -- Public mapping allows any login on this instance to reach the remote server
    CASE
        WHEN lsl.local_principal_id = 0
        THEN 'PUBLIC_MAPPING_RISK'
        ELSE ''
    END                                                     AS SecurityFlag
FROM sys.servers ls
LEFT JOIN sys.linked_logins lsl   ON lsl.server_id     = ls.server_id
LEFT JOIN sys.server_principals sp ON sp.principal_id  = lsl.local_principal_id
WHERE ls.is_linked = 1
ORDER BY ls.name;

GO

-- ── Part 2: Credentials (used by Agent proxies, external processes, etc.) ─────
SELECT
    c.credential_id,
    c.name                                                  AS CredentialName,
    c.credential_identity                                   AS CredentialIdentity,
    c.create_date,
    c.modify_date,
    c.target_type                                           AS TargetType
FROM sys.credentials c
ORDER BY c.name;
