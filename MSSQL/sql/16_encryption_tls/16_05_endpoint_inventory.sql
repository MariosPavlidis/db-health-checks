-- ============================================================
-- Health Check: Ch 16 Encryption, TLS — 16.5 Endpoint Inventory
-- Checklist ref: Section 16.5
-- Min SQL version: 2016 (130)
-- ============================================================
-- Lists all SQL Server endpoints with type, protocol, state, and connection
-- permissions.  Flags endpoints that are STOPPED/DISABLED, deprecated
-- (database mirroring), or have unexpectedly broad CONNECT grants.
-- Endpoint types covered:
--   1 = SOAP (HTTP)        — deprecated in SQL 2022
--   2 = TSQL               — the default shared listener endpoint
--   3 = SERVICE_BROKER
--   4 = DATABASE_MIRRORING — deprecated feature
--   5 = HADR (AG endpoint)
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- ── 1. Endpoint inventory ─────────────────────────────────────────────────────
SELECT
    ep.name                                         AS EndpointName,
    ep.endpoint_id,
    ep.type_desc                                    AS EndpointType,
    ep.protocol_desc                                AS Protocol,
    ep.state_desc                                   AS State,
    ep.is_admin_endpoint                            AS IsAdminEndpoint,
    -- TCP-specific details (most endpoints use TCP)
    tcp.port                                        AS TCPPort,
    tcp.is_dynamic_port                             AS IsDynamicPort,
    tcp.ip_address                                  AS ListenIP,
    http.clear_port                                 AS HTTPClearPort,
    http.ssl_port                                   AS HTTPSslPort,
    ep.create_date                                  AS CreateDate,
    ep.modify_date                                  AS ModifyDate,
    CASE
        WHEN ep.type_desc = 'DATABASE_MIRRORING'
             THEN 'DEPRECATED_ENDPOINT'
        WHEN ep.type_desc = 'SOAP'
             THEN 'DEPRECATED_SOAP_ENDPOINT'
        WHEN ep.state_desc = 'STOPPED'
             THEN 'ENDPOINT_STOPPED'
        WHEN ep.state_desc = 'DISABLED'
             THEN 'ENDPOINT_DISABLED'
        ELSE ''
    END                                             AS EndpointFlag
FROM sys.endpoints ep
LEFT JOIN sys.tcp_endpoints   tcp  ON tcp.endpoint_id  = ep.endpoint_id
LEFT JOIN sys.http_endpoints  http ON http.endpoint_id = ep.endpoint_id
ORDER BY ep.type_desc, ep.name;

-- ── 2. CONNECT permissions on endpoints ───────────────────────────────────────
SELECT
    ep.name                                         AS EndpointName,
    ep.type_desc                                    AS EndpointType,
    ep.state_desc                                   AS State,
    CASE p.state_desc
        WHEN 'GRANT'  THEN 'GRANT'
        WHEN 'DENY'   THEN 'DENY'
        WHEN 'REVOKE' THEN 'REVOKE'
        ELSE p.state_desc
    END                                             AS PermissionState,
    p.type                                          AS PermType,
    pr.name                                         AS PrincipalName,
    pr.type_desc                                    AS PrincipalType,
    CASE
        WHEN p.grantee_principal_id = 0
             THEN 'PUBLIC_CONNECT_GRANT'            -- public role = anyone can connect
        WHEN pr.type = 'S'
             AND p.state_desc = 'GRANT'             THEN 'SQL_LOGIN_CONNECT'
        ELSE ''
    END                                             AS ConnectFlag
FROM sys.server_permissions p
JOIN sys.endpoints ep
    ON ep.endpoint_id = p.major_id
LEFT JOIN sys.server_principals pr
    ON pr.principal_id = p.grantee_principal_id
WHERE p.class = 105          -- ENDPOINT
  AND p.type  = 'CO'         -- CONNECT
ORDER BY ep.type_desc, ep.name, pr.name;
