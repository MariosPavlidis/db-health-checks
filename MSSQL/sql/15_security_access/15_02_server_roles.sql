-- ============================================================
-- Health Check: Ch 15 Security and Access — 15.2 Server Roles and Permissions
-- Checklist ref: Section 15.2
-- Min SQL version: 2016 (130)
-- ============================================================
-- Part 1: Fixed server role membership — identifies disabled members and
--         possible personal accounts in privileged roles.
-- Part 2: Explicit server-level permission grants (non-role GRANT/DENY) —
--         flags high-privilege permissions such as CONTROL SERVER.
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- ── Part 1: Fixed server role membership ─────────────────────────────────────
SELECT
    r.name                                                  AS ServerRole,
    m.name                                                  AS MemberName,
    m.type_desc                                             AS MemberType,
    m.is_disabled                                           AS MemberIsDisabled,
    m.create_date                                           AS MemberCreateDate,
    m.modify_date                                           AS MemberModifyDate,
    CASE WHEN m.is_disabled = 1
         THEN 'DISABLED_MEMBER'
         ELSE '' END                                        AS DisabledMemberFlag,
    -- Non-Windows, non-SA SQL logins in a server role — likely personal accounts
    CASE
        WHEN m.name NOT LIKE 'NT %'
         AND m.name NOT LIKE '%\%'
         AND m.type = 'S'
         AND m.name NOT IN ('sa')
        THEN 'POSSIBLE_PERSONAL_ACCOUNT'
        ELSE ''
    END                                                     AS PersonalAccountFlag
FROM sys.server_role_members rm
JOIN sys.server_principals r ON r.principal_id = rm.role_principal_id
JOIN sys.server_principals m ON m.principal_id = rm.member_principal_id
ORDER BY r.name, m.name;

GO

-- ── Part 2: Explicit server-level permissions (non-role grants) ───────────────
SELECT
    sp.state_desc                                           AS PermissionState,
    sp.permission_name                                      AS Permission,
    sp.class_desc                                           AS Class,
    pr.name                                                 AS Grantee,
    pr.type_desc                                            AS GranteeType,
    gr.name                                                 AS Grantor,
    -- Flag permissions that carry significant administrative capability
    CASE
        WHEN sp.permission_name IN (
            'CONTROL SERVER',
            'ALTER ANY LOGIN',
            'IMPERSONATE ANY LOGIN',
            'ALTER ANY SERVER ROLE',
            'CREATE ANY DATABASE',
            'ALTER ANY LINKED SERVER',
            'ADMINISTER BULK OPERATIONS',
            'EXTERNAL ACCESS ASSEMBLY',
            'UNSAFE ASSEMBLY'
        )
        THEN 'HIGH_PRIVILEGE'
        ELSE ''
    END                                                     AS HighPrivilegeFlag
FROM sys.server_permissions sp
JOIN sys.server_principals pr ON pr.principal_id = sp.grantee_principal_id
JOIN sys.server_principals gr ON gr.principal_id = sp.grantor_principal_id
WHERE sp.class = 100  -- server-scope permissions only
ORDER BY sp.permission_name, pr.name;
