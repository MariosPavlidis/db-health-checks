-- ============================================================
-- Health Check: Ch 22 Maintenance and Operational Governance — 22.3 Configuration Ownership
-- Checklist ref: Section 22.3
-- Min SQL version: 2016 (130)
-- ============================================================
-- Reviews ownership of SQL Agent jobs and databases for personal accounts,
-- disabled logins, or accounts that are not clearly identifiable service
-- accounts. Also surfaces certificates as an informational ownership check.
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- Job ownership review
SELECT
    j.name                                          AS JobName,
    SUSER_SNAME(j.owner_sid)                        AS Owner,
    sp.is_disabled                                  AS OwnerDisabled,
    CASE WHEN sp.is_disabled = 1
              THEN 'DISABLED_OWNER'
         WHEN SUSER_SNAME(j.owner_sid) NOT LIKE 'NT %'
              AND SUSER_SNAME(j.owner_sid) NOT LIKE '%\%'
              AND SUSER_SNAME(j.owner_sid) NOT IN ('sa')
              AND SUSER_SNAME(j.owner_sid) IS NOT NULL
              THEN 'POSSIBLE_PERSONAL_OWNER'
         ELSE ''
    END                                             AS OwnerFlag,
    j.enabled                                       AS JobEnabled,
    j.date_modified                                 AS LastModified
FROM msdb.dbo.sysjobs j
LEFT JOIN sys.server_principals sp
    ON sp.sid = j.owner_sid
ORDER BY OwnerFlag DESC, j.name;

GO

-- Database ownership review
SELECT
    d.name                                          AS DatabaseName,
    d.owner_sid,
    SUSER_SNAME(d.owner_sid)                        AS Owner,
    sp.is_disabled                                  AS OwnerDisabled,
    d.state_desc                                    AS State,
    d.recovery_model_desc                           AS RecoveryModel,
    CASE WHEN sp.is_disabled = 1
              THEN 'DISABLED_OWNER'
         WHEN SUSER_SNAME(d.owner_sid) NOT LIKE 'NT %'
              AND SUSER_SNAME(d.owner_sid) NOT LIKE '%\%'
              AND SUSER_SNAME(d.owner_sid) NOT IN ('sa')
              AND SUSER_SNAME(d.owner_sid) IS NOT NULL
              THEN 'POSSIBLE_PERSONAL_OWNER'
         ELSE ''
    END                                             AS OwnerFlag
FROM sys.databases d
LEFT JOIN sys.server_principals sp
    ON sp.sid = d.owner_sid
ORDER BY OwnerFlag DESC, d.name;

GO

-- Certificate inventory (informational — flag absence of documented owners)
SELECT
    c.name                                          AS CertificateName,
    c.subject                                       AS Subject,
    c.expiry_date                                   AS ExpiryDate,
    DATEDIFF(DAY, GETDATE(), c.expiry_date)         AS DaysUntilExpiry,
    c.start_date                                    AS StartDate,
    c.pvt_key_encryption_type_desc                  AS PrivateKeyEncryptionType,
    c.is_active_for_begin_dialog                    AS ActiveForDialog,
    DB_NAME()                                       AS DatabaseName,
    CASE WHEN c.expiry_date < GETDATE()             THEN 'EXPIRED'
         WHEN DATEDIFF(DAY, GETDATE(), c.expiry_date) < 90 THEN 'EXPIRING_SOON'
         ELSE 'INFO'
    END                                             AS CertFlag
FROM sys.certificates c
ORDER BY c.expiry_date;
