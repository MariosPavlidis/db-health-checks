-- ============================================================
-- Health Check: Ch 16 Encryption, TLS, and Certificates — 16.4 Certificate Expiry Summary
-- Checklist ref: Section 16.4
-- Min SQL version: 2016 (130)
-- ============================================================
-- Enumerates all SQL Server internal certificates (from the current database
-- context — run against master for service broker and endpoint certs) and
-- classifies their expiry status using the standard thresholds:
--   EXPIRED   = already past expiry_date
--   CRITICAL  = expires within 30 days
--   HIGH      = expires within 90 days
--   WARNING   = expires within 180 days
--   OK        = more than 180 days remaining
-- Windows TLS certificates (Windows Certificate Store) are checked separately
-- in the PowerShell section 16_01b.
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

SELECT
    c.name                                                  AS CertificateName,
    c.subject                                               AS Subject,
    c.issuer_name                                           AS Issuer,
    c.cert_serial_number                                    AS SerialNumber,
    c.start_date                                            AS ValidFrom,
    c.expiry_date                                           AS ValidTo,
    DATEDIFF(DAY, GETDATE(), c.expiry_date)                 AS DaysUntilExpiry,
    c.pvt_key_encryption_type_desc                          AS PrivateKeyEncryption,
    c.is_active_for_begin_dialog                            AS IsActiveForDialog,
    DB_NAME()                                               AS CertificateDatabase,
    CASE
        WHEN c.expiry_date < GETDATE()                      THEN 'EXPIRED'
        WHEN DATEDIFF(DAY, GETDATE(), c.expiry_date) < 30  THEN 'CRITICAL'
        WHEN DATEDIFF(DAY, GETDATE(), c.expiry_date) < 90  THEN 'HIGH'
        WHEN DATEDIFF(DAY, GETDATE(), c.expiry_date) < 180 THEN 'WARNING'
        ELSE 'OK'
    END                                                     AS ExpiryFlag,
    'SQL_INTERNAL'                                          AS CertSource
FROM sys.certificates c
ORDER BY c.expiry_date;
