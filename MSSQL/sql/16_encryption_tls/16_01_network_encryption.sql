-- ============================================================
-- Health Check: Ch 16 Encryption, TLS, and Certificates — 16.1 Network Encryption
-- Checklist ref: Section 16.1
-- Min SQL version: 2016 (130)
-- ============================================================
-- Part 1: Active connection encryption status grouped by transport, protocol,
--         and auth scheme — shows how many connections are encrypted vs. plain.
-- Part 2: Instance-level encryption configuration (ForceEncryption sp_configure
--         and SERVERPROPERTY for the current connection's encryption state).
-- Part 3: Certificate thumbprint configured for SQL Server TLS via registry
--         (read with xp_instance_regread from SuperSocketNetLib).
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- ── Part 1: Connection encryption summary ────────────────────────────────────
SELECT
    net_transport                                           AS Transport,
    encrypt_option                                          AS EncryptOption,
    auth_scheme                                             AS AuthScheme,
    protocol_type                                           AS ProtocolType,
    protocol_version                                        AS ProtocolVersion,
    COUNT(*)                                                AS ConnectionCount
FROM sys.dm_exec_connections
GROUP BY net_transport, encrypt_option, auth_scheme, protocol_type, protocol_version
ORDER BY ConnectionCount DESC;

GO

-- ── Part 2: Instance encryption configuration ────────────────────────────────
SELECT
    CAST(SERVERPROPERTY('IsEncryptedConnection') AS INT)    AS IsEncryptedConnection,
    (   SELECT value_in_use
        FROM sys.configurations
        WHERE name = 'force encryption'
    )                                                       AS ForceEncryptionConfig;

GO

-- ── Part 3: TLS certificate thumbprint from registry ─────────────────────────
-- Returns the thumbprint of the certificate SQL Server is configured to use
-- for TLS.  An empty result means SQL Server is using a self-signed certificate
-- generated at startup (not the Windows certificate store).
EXEC xp_instance_regread
    N'HKEY_LOCAL_MACHINE',
    N'SOFTWARE\Microsoft\Microsoft SQL Server\MSSQLServer\SuperSocketNetLib',
    N'Certificate';
