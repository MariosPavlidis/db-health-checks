-- ============================================================
-- Health Check: Ch 16 Encryption, TLS, and Certificates — 16.2 TDE Status
-- Checklist ref: Section 16.2
-- Min SQL version: 2016 (130)
-- ============================================================
-- Transparent Data Encryption state for all databases.
-- Joins sys.dm_database_encryption_keys and sys.certificates to surface
-- certificate validity and expiry.  Databases without a DEK entry are
-- unencrypted.  Flags certificates expiring within 30 / 90 / 180 days.
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

SELECT
    db.name                                                 AS DatabaseName,
    db.database_id,
    dek.encryption_state                                    AS EncryptionStateCode,
    CASE dek.encryption_state
        WHEN 0 THEN 'No encryption'
        WHEN 1 THEN 'Unencrypted'
        WHEN 2 THEN 'Encryption in progress'
        WHEN 3 THEN 'Encrypted'
        WHEN 4 THEN 'Key change in progress'
        WHEN 5 THEN 'Decryption in progress'
        WHEN 6 THEN 'Protection change in progress'
        END                                                 AS EncryptionStateDesc,
    dek.percent_complete                                    AS EncryptionProgressPct,
    dek.encryptor_type                                      AS EncryptorType,
    dek.key_algorithm                                       AS KeyAlgorithm,
    dek.key_length                                          AS KeyLength,
    c.name                                                  AS CertificateName,
    c.subject                                               AS CertificateSubject,
    c.start_date                                            AS CertificateValidFrom,
    c.expiry_date                                           AS CertificateExpiry,
    DATEDIFF(DAY, GETDATE(), c.expiry_date)                 AS DaysUntilExpiry,
    CASE
        WHEN c.expiry_date IS NULL              THEN 'N/A'
        WHEN c.expiry_date < GETDATE()          THEN 'EXPIRED'
        WHEN DATEDIFF(DAY, GETDATE(), c.expiry_date) < 30  THEN 'CRITICAL'
        WHEN DATEDIFF(DAY, GETDATE(), c.expiry_date) < 90  THEN 'HIGH'
        WHEN DATEDIFF(DAY, GETDATE(), c.expiry_date) < 180 THEN 'WARNING'
        ELSE 'OK'
    END                                                     AS CertExpiryFlag,
    dek.create_date                                         AS EncryptionKeyCreated,
    dek.regenerate_date                                     AS KeyRegenerateDate,
    dek.set_date                                            AS KeySetDate,
    dek.opened_date                                         AS KeyOpenedDate
FROM sys.databases db
LEFT JOIN sys.dm_database_encryption_keys dek
    ON dek.database_id = db.database_id
LEFT JOIN sys.certificates c
    ON c.thumbprint = dek.encryptor_thumbprint
ORDER BY db.name;
