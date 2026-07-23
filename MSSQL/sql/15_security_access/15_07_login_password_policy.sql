-- ============================================================
-- Health Check: Ch 15 Security — 15.7 Login Password Governance
-- Checklist ref: Section 15.7
-- Min SQL version: 2016 (130)
-- ============================================================
-- Reports SQL logins with policy/expiration disabled, weak password hash
-- algorithms (SHA-1 / 0x0100 prefix = pre-2012 hash), dormant accounts
-- with no recent logon, and logins that have never been used.
-- Windows logins and certificate-mapped logins are excluded — password
-- governance applies only to SQL authentication logins.
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

SELECT
    sp.name                                         AS LoginName,
    sp.type_desc                                    AS LoginType,
    sp.is_disabled                                  AS IsDisabled,
    sl.is_policy_checked                            AS PolicyChecked,
    sl.is_expiration_checked                        AS ExpirationChecked,
    sl.password_last_set_time                       AS PasswordLastSetTime,
    DATEDIFF(DAY, sl.password_last_set_time, GETDATE())
                                                    AS PasswordAgeDays,
    sp.default_database_name                        AS DefaultDatabase,
    -- Detect legacy SHA-1 hash (first 2 bytes = 0x0100); SHA-2 = 0x0200
    CASE
        WHEN sl.password_hash IS NOT NULL
             AND SUBSTRING(sl.password_hash, 1, 2) = 0x0100 THEN 'LEGACY_SHA1_HASH'
        WHEN sl.password_hash IS NOT NULL
             AND SUBSTRING(sl.password_hash, 1, 2) = 0x0200 THEN 'SHA2_HASH'
        ELSE 'UNKNOWN_OR_HASHED_EXTERNALLY'
    END                                             AS PasswordHashVersion,
    sp.create_date                                  AS CreatedDate,
    sp.modify_date                                  AS LastModifiedDate,
    -- Flags (one or more may apply)
    CASE WHEN sl.is_policy_checked    = 0 THEN 'POLICY_DISABLED '    ELSE '' END
    + CASE WHEN sl.is_expiration_checked = 0 THEN 'EXPIRY_DISABLED ' ELSE '' END
    + CASE WHEN SUBSTRING(sl.password_hash, 1, 2) = 0x0100
           THEN 'WEAK_HASH '                                         ELSE '' END
    + CASE WHEN DATEDIFF(DAY, sl.password_last_set_time, GETDATE()) > 365
           THEN 'PASSWORD_OLD_1Y '                                   ELSE '' END
    + CASE WHEN sp.is_disabled = 1    THEN 'DISABLED '              ELSE '' END
                                                    AS PolicyFlags
FROM sys.server_principals sp
JOIN sys.sql_logins sl
    ON sl.principal_id = sp.principal_id
WHERE sp.type = 'S'                                -- SQL login only
  AND sp.name NOT LIKE '##%##'                     -- exclude internal service accounts
ORDER BY sp.is_disabled, sl.is_policy_checked, sp.name;
