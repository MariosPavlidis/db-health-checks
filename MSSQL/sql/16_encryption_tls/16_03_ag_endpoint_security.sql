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
        te.port                                                 AS Port,
        te.connection_auth_desc                                 AS AuthType,
        te.encryption_auth_desc                                 AS EncryptionType,
        te.encryption_algorithm_desc                            AS EncryptionAlgorithm,
        -- CONNECT permission details
        ep.state_desc                                           AS PermissionState,
        ep.permission_name                                      AS Permission,
        pr.name                                                 AS Grantee,
        pr.type_desc                                            AS GranteeType,
        -- Certificate info (only populated when certificate-based auth is configured)
        c.name                                                  AS CertificateName,
        c.expiry_date                                           AS CertExpiry,
        DATEDIFF(DAY, GETDATE(), c.expiry_date)                 AS CertDaysUntilExpiry,
        CASE
            WHEN c.expiry_date IS NULL              THEN 'N/A'
            WHEN c.expiry_date < GETDATE()          THEN 'EXPIRED'
            WHEN DATEDIFF(DAY, GETDATE(), c.expiry_date) < 30  THEN 'CRITICAL'
            WHEN DATEDIFF(DAY, GETDATE(), c.expiry_date) < 90  THEN 'HIGH'
            WHEN DATEDIFF(DAY, GETDATE(), c.expiry_date) < 180 THEN 'WARNING'
            ELSE 'OK'
        END                                                     AS CertExpiryFlag
    FROM sys.endpoints e
    JOIN sys.database_mirroring_endpoints te
        ON te.endpoint_id = e.endpoint_id
    LEFT JOIN sys.server_permissions ep
        ON  ep.major_id  = e.endpoint_id
        AND ep.class     = 105              -- ENDPOINT class
        AND ep.type      = 'CO'            -- CONNECT permission
    LEFT JOIN sys.server_principals pr
        ON pr.principal_id = ep.grantee_principal_id
    -- Match certificate by name if connection auth is certificate-based
    LEFT JOIN sys.certificates c
        ON c.name = te.connection_auth_desc
    ORDER BY e.name;
END
ELSE
BEGIN
    SELECT 'HADR not enabled - AG endpoint security not applicable' AS Note;
END
