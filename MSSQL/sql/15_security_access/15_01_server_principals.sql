-- ============================================================
-- Health Check: Ch 15 Security and Access — 15.1 Server Principals
-- Checklist ref: Section 15.1
-- Min SQL version: 2016 (130)
-- ============================================================
-- Enumerates all server-level principals (logins): SQL auth, Windows users,
-- Windows groups, certificate-mapped, and external provider logins.
-- Flags disabled logins, SQL auth logins, possible personal accounts,
-- and invalid default databases.
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

SELECT
    sp.principal_id,
    sp.name                                                 AS LoginName,
    sp.type_desc                                            AS LoginType,
    sp.is_disabled                                          AS IsDisabled,
    sp.create_date                                          AS CreateDate,
    sp.modify_date                                          AS ModifyDate,
    sp.default_database_name                                AS DefaultDatabase,
    sp.default_language_name                                AS DefaultLanguage,
    sl.is_policy_checked                                    AS PasswordPolicyChecked,
    sl.is_expiration_checked                                AS PasswordExpirationChecked,
    -- Mapped credential (if any)
    c.name                                                  AS MappedCredential,
    -- Flags
    CASE WHEN sp.is_disabled = 1
         THEN 'DISABLED'
         ELSE '' END                                        AS DisabledFlag,
    CASE WHEN sp.type = 'S'
         THEN 'SQL_AUTH_LOGIN'
         ELSE '' END                                        AS SqlAuthFlag,
    -- Logins that are not Windows accounts, not service accounts, not SA,
    -- and not prefixed with common service patterns — likely a personal account.
    CASE
        WHEN sp.name NOT LIKE '%\%'
         AND sp.name NOT LIKE 'NT %'
         AND sp.type = 'S'
         AND sp.name NOT IN ('sa')
         AND sp.name NOT LIKE 'svc%'
         AND sp.name NOT LIKE '%service%'
         AND sp.name NOT LIKE '%agent%'
        THEN 'POSSIBLE_PERSONAL_ACCOUNT'
        ELSE ''
    END                                                     AS PersonalAccountFlag,
    -- Login whose default database no longer exists
    CASE WHEN DB_ID(sp.default_database_name) IS NULL
         THEN 'INVALID_DEFAULT_DB'
         ELSE '' END                                        AS InvalidDefaultDbFlag,
    DATEDIFF(DAY, sp.modify_date, GETDATE())                AS DaysSinceModified
FROM sys.server_principals sp
LEFT JOIN sys.sql_logins sl ON sl.principal_id = sp.principal_id
LEFT JOIN sys.credentials c ON c.credential_id = sp.credential_id
WHERE sp.type IN ('S', 'U', 'G', 'C', 'E', 'X')  -- SQL, Windows user, group, cert, ext provider, ext group
  AND sp.name NOT LIKE '##%'                        -- exclude internally generated certificate logins
ORDER BY sp.type_desc, sp.name;
