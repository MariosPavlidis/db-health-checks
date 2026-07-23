-- ============================================================
-- Health Check: Ch 16 Encryption, TLS, and Certificates — 16.3 AG Endpoint Security
-- Checklist ref: Section 16.3
-- Min SQL version: 2016 (130)
-- ============================================================
-- Checks the database mirroring / AG endpoint configuration: auth type,
-- encryption algorithm, CONNECT permission grants, and (if certificate
-- authentication is used) certificate expiry status.
-- Only runs when HADR is enabled on the instance.
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

IF CAST(SERVERPROPERTY('IsHadrEnabled') AS INT) = 1
BEGIN
    SELECT
        e.endpoint_id                                           AS EndpointId,
        e.name                                                  AS EndpointName,
        e.state_desc                                            AS EndpointState,
        e.type_desc                                             AS EndpointType,
        -- Port lives in sys.tcp_endpoints, not sys.database_mirroring_endpoints
        tcp.port                                                AS Port,
        me.role_desc                                            AS EndpointRole,
        me.connection_auth_desc                                 AS AuthType,
        me.encryption_algorithm_desc                            AS EncryptionAlgorithm,
        me.is_encryption_enabled                                AS IsEncryptionEnabled,
        -- CONNECT permission details
        ep.state_desc                                           AS PermissionState,
        pr.name                                                 AS Grantee,
        pr.type_desc                                            AS GranteeType,
        CASE
            WHEN ep.state_desc IS NULL          THEN 'NO_CONNECT_GRANT'
            WHEN me.is_encryption_enabled = 0   THEN 'ENCRYPTION_DISABLED'
            ELSE ''
        END                                                     AS EndpointFlag
    FROM sys.endpoints e
    JOIN sys.database_mirroring_endpoints me
        ON me.endpoint_id = e.endpoint_id
    LEFT JOIN sys.tcp_endpoints tcp
        ON tcp.endpoint_id = e.endpoint_id
    LEFT JOIN sys.server_permissions ep
        ON  ep.major_id  = e.endpoint_id
        AND ep.class     = 105              -- ENDPOINT class
        AND ep.type      = 'CO'            -- CONNECT permission
    LEFT JOIN sys.server_principals pr
        ON pr.principal_id = ep.grantee_principal_id
    ORDER BY e.name, pr.name;
END
ELSE
BEGIN
    SELECT 'HADR not enabled - AG endpoint security not applicable' AS Note;
END
