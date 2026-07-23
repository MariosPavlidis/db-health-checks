-- ============================================================
-- Health Check: Ch 16 Encryption, TLS — 16.8 TDE Scan Progress and Key Availability
-- Checklist ref: Section 16.8
-- Min SQL version: 2016 (130)
-- ============================================================
-- Complements 16_02_tde.sql with two specific checks:
-- Query 1: Databases currently mid-encryption/decryption scan (states 2, 4, 5, 6)
--           with percent_complete to track progress of in-flight operations.
-- Query 2: TDE-encrypted databases that participate in an Availability Group —
--           the protecting certificate must be present on EVERY AG replica.
--           This query lists the certificate details so the operator can verify
--           the certificate is installed on each secondary.
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- ── 1. Active TDE scan operations (encryption/decryption in progress) ─────────
SELECT
    d.name                                          AS DatabaseName,
    dek.encryption_state                            AS EncryptionStateCode,
    CASE dek.encryption_state
        WHEN 2 THEN 'Encryption in progress'
        WHEN 4 THEN 'Key change in progress'
        WHEN 5 THEN 'Decryption in progress'
        WHEN 6 THEN 'Protection change in progress'
        ELSE        'Other state'
    END                                             AS EncryptionStateDesc,
    dek.percent_complete                            AS PercentComplete,
    dek.encryptor_type                              AS EncryptorType,
    dek.key_algorithm                               AS KeyAlgorithm,
    dek.key_length                                  AS KeyLengthBits,
    dek.create_date                                 AS KeyCreateDate,
    dek.set_date                                    AS KeySetDate
FROM sys.databases d
JOIN sys.dm_database_encryption_keys dek
    ON dek.database_id = d.database_id
WHERE dek.encryption_state IN (2, 4, 5, 6)     -- mid-scan states
ORDER BY d.name;

-- ── 2. TDE-encrypted databases in Availability Groups ────────────────────────
-- The certificate listed here MUST exist on every AG secondary replica.
-- Verify by running:  SELECT name FROM sys.certificates  on each replica.
SELECT
    d.name                                          AS DatabaseName,
    ag.name                                         AS AGName,
    ar.replica_server_name                          AS ReplicaServer,
    ars.role_desc                                   AS ReplicaRole,
    dek.encryption_state                            AS EncryptionState,
    CASE dek.encryption_state
        WHEN 3 THEN 'Encrypted'
        ELSE        'Not fully encrypted'
    END                                             AS TDEState,
    c.name                                          AS ProtectingCertName,
    c.subject                                       AS CertSubject,
    c.expiry_date                                   AS CertExpiry,
    DATEDIFF(DAY, GETDATE(), c.expiry_date)         AS CertDaysUntilExpiry,
    CASE
        WHEN c.expiry_date < GETDATE()              THEN 'CERT_EXPIRED'
        WHEN DATEDIFF(DAY, GETDATE(), c.expiry_date) < 90 THEN 'CERT_EXPIRY_WARN'
        ELSE ''
    END                                             AS CertExpiryFlag,
    'Verify cert ''' + ISNULL(c.name, '?')
    + ''' exists on: ' + ar.replica_server_name     AS VerifyInstruction
FROM sys.databases d
JOIN sys.dm_database_encryption_keys dek
    ON dek.database_id = d.database_id
   AND dek.encryption_state = 3                    -- fully encrypted only
LEFT JOIN sys.certificates c
    ON c.thumbprint = dek.encryptor_thumbprint
-- Join to AG membership to find replicas
JOIN sys.dm_hadr_database_replica_states drs
    ON drs.group_database_id = d.group_database_id
JOIN sys.availability_replicas ar
    ON ar.replica_id = drs.replica_id
JOIN sys.availability_groups ag
    ON ag.group_id = ar.group_id
JOIN sys.dm_hadr_availability_replica_states ars
    ON ars.replica_id = ar.replica_id
ORDER BY d.name, ars.role_desc, ar.replica_server_name;
