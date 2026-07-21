-- ============================================================
-- Health Check: Ch 15 Security and Access — 15.5 SA Account and Sysadmin Members
-- Checklist ref: Section 15.5
-- Min SQL version: 2016 (130)
-- ============================================================
-- Part 1: SA account status — detects the original SA login and any renamed
--         SA (principal_id = 1 but name != 'sa').  Also checks for high-risk
--         built-in Windows accounts granted server access.
-- Part 2: Full sysadmin role membership for emergency access review.
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- ── Part 1: SA and built-in privileged accounts ───────────────────────────────
-- principal_id = 1 is always the SA account regardless of whether it has been renamed.
SELECT
    name                                                    AS LoginName,
    is_disabled                                             AS IsDisabled,
    type_desc                                               AS LoginType,
    CASE WHEN name = 'sa'         THEN 'ORIGINAL_SA'  ELSE '' END AS SaFlag,
    CASE WHEN name != 'sa' AND principal_id = 1
                                  THEN 'RENAMED_SA'   ELSE '' END AS RenamedSaFlag,
    create_date,
    modify_date
FROM sys.server_principals
WHERE principal_id = 1   -- SID 0x01 — always SA

UNION ALL

-- Built-in Windows accounts that should generally not have direct SQL Server access
SELECT
    name,
    is_disabled,
    type_desc,
    'BUILTIN_ADMIN'                                         AS SaFlag,
    ''                                                      AS RenamedSaFlag,
    create_date,
    modify_date
FROM sys.server_principals
WHERE name IN (
    'BUILTIN\Administrators',
    'NT AUTHORITY\SYSTEM',
    'NT AUTHORITY\NETWORK SERVICE'
)
  AND principal_id != 1   -- avoid double-listing if SA is one of these (unlikely but safe)

ORDER BY SaFlag;

GO

-- ── Part 2: Sysadmin role membership ─────────────────────────────────────────
SELECT
    m.name                                                  AS SysadminMember,
    m.type_desc                                             AS LoginType,
    m.is_disabled                                           AS IsDisabled,
    m.create_date,
    m.modify_date
FROM sys.server_role_members rm
JOIN sys.server_principals r ON r.principal_id = rm.role_principal_id
                              AND r.name = 'sysadmin'
JOIN sys.server_principals m ON m.principal_id = rm.member_principal_id
ORDER BY m.name;
