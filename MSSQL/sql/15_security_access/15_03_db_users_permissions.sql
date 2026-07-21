-- ============================================================
-- Health Check: Ch 15 Security and Access — 15.3 Database Users and Permissions
-- Checklist ref: Section 15.3
-- Min SQL version: 2016 (130)
-- ============================================================
-- Iterates all ONLINE user databases via cursor and collects database users,
-- their mapped server login, role membership, and key security flags:
--   - Orphaned users (no matching server login SID)
--   - Guest user enabled
--   - db_owner role membership
-- STRING_AGG is used for SQL 2017+; a FOR XML PATH fallback covers SQL 2016.
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- Results accumulation table
CREATE TABLE #DbUsers (
    DatabaseName        SYSNAME,
    UserName            SYSNAME,
    UserType            NVARCHAR(60),
    AuthType            NVARCHAR(60),
    CreateDate          DATETIME,
    ModifyDate          DATETIME,
    DefaultSchema       SYSNAME        NULL,
    MappedLogin         SYSNAME        NULL,
    LoginIsDisabled     BIT            NULL,
    RoleMembership      NVARCHAR(MAX)  NULL,
    OrphanedUserFlag    NVARCHAR(30)   NOT NULL DEFAULT '',
    GuestFlag           NVARCHAR(20)   NOT NULL DEFAULT '',
    DbOwnerFlag         NVARCHAR(20)   NOT NULL DEFAULT ''
);

DECLARE @dbName  SYSNAME;
DECLARE @sql     NVARCHAR(MAX);
DECLARE @ver     INT = CAST(SERVERPROPERTY('ProductMajorVersion') AS INT);

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM sys.databases
    WHERE database_id > 4
      AND state_desc = 'ONLINE'
      AND is_read_only = 0
    ORDER BY name;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @dbName;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- Use STRING_AGG (SQL 2017+) or FOR XML PATH fallback (SQL 2016)
    IF @ver >= 14
        SET @sql = N'
USE ' + QUOTENAME(@dbName) + N';
INSERT INTO #DbUsers (DatabaseName, UserName, UserType, AuthType, CreateDate, ModifyDate,
                      DefaultSchema, MappedLogin, LoginIsDisabled, RoleMembership,
                      OrphanedUserFlag, GuestFlag, DbOwnerFlag)
SELECT
    DB_NAME()                                               AS DatabaseName,
    dp.name                                                 AS UserName,
    dp.type_desc                                            AS UserType,
    dp.authentication_type_desc                             AS AuthType,
    dp.create_date,
    dp.modify_date,
    dp.default_schema_name                                  AS DefaultSchema,
    sl.name                                                 AS MappedLogin,
    sl.is_disabled                                          AS LoginIsDisabled,
    (   SELECT STRING_AGG(r.name, '','')
        FROM sys.database_role_members rm
        JOIN sys.database_principals r ON r.principal_id = rm.role_principal_id
        WHERE rm.member_principal_id = dp.principal_id
    )                                                       AS RoleMembership,
    CASE WHEN sl.sid IS NULL AND dp.sid IS NOT NULL
              AND dp.type NOT IN (''R'',''A'')
         THEN ''ORPHANED_USER'' ELSE '''' END               AS OrphanedUserFlag,
    CASE WHEN dp.name = ''guest'' THEN ''GUEST_USER'' ELSE '''' END AS GuestFlag,
    CASE WHEN EXISTS (
             SELECT 1
             FROM sys.database_role_members rm
             JOIN sys.database_principals r ON r.principal_id = rm.role_principal_id
             WHERE rm.member_principal_id = dp.principal_id AND r.name = ''db_owner''
         )
         THEN ''DB_OWNER_MEMBER'' ELSE '''' END              AS DbOwnerFlag
FROM sys.database_principals dp
LEFT JOIN sys.server_principals sl ON sl.sid = dp.sid
WHERE dp.type IN (''S'',''U'',''G'',''C'',''E'',''X'')
ORDER BY dp.name;';
    ELSE
        -- SQL 2016 fallback: FOR XML PATH for role list
        SET @sql = N'
USE ' + QUOTENAME(@dbName) + N';
INSERT INTO #DbUsers (DatabaseName, UserName, UserType, AuthType, CreateDate, ModifyDate,
                      DefaultSchema, MappedLogin, LoginIsDisabled, RoleMembership,
                      OrphanedUserFlag, GuestFlag, DbOwnerFlag)
SELECT
    DB_NAME()                                               AS DatabaseName,
    dp.name                                                 AS UserName,
    dp.type_desc                                            AS UserType,
    dp.authentication_type_desc                             AS AuthType,
    dp.create_date,
    dp.modify_date,
    dp.default_schema_name                                  AS DefaultSchema,
    sl.name                                                 AS MappedLogin,
    sl.is_disabled                                          AS LoginIsDisabled,
    STUFF((
        SELECT '','' + r.name
        FROM sys.database_role_members rm
        JOIN sys.database_principals r ON r.principal_id = rm.role_principal_id
        WHERE rm.member_principal_id = dp.principal_id
        FOR XML PATH(''''), TYPE
    ).value(''.'',''NVARCHAR(MAX)''), 1, 1, '''')           AS RoleMembership,
    CASE WHEN sl.sid IS NULL AND dp.sid IS NOT NULL
              AND dp.type NOT IN (''R'',''A'')
         THEN ''ORPHANED_USER'' ELSE '''' END               AS OrphanedUserFlag,
    CASE WHEN dp.name = ''guest'' THEN ''GUEST_USER'' ELSE '''' END AS GuestFlag,
    CASE WHEN EXISTS (
             SELECT 1
             FROM sys.database_role_members rm
             JOIN sys.database_principals r ON r.principal_id = rm.role_principal_id
             WHERE rm.member_principal_id = dp.principal_id AND r.name = ''db_owner''
         )
         THEN ''DB_OWNER_MEMBER'' ELSE '''' END              AS DbOwnerFlag
FROM sys.database_principals dp
LEFT JOIN sys.server_principals sl ON sl.sid = dp.sid
WHERE dp.type IN (''S'',''U'',''G'',''C'',''E'',''X'')
ORDER BY dp.name;';

    BEGIN TRY
        EXEC sp_executesql @sql;
    END TRY
    BEGIN CATCH
        -- Log the failing database but continue
        INSERT INTO #DbUsers (DatabaseName, UserName, UserType, AuthType, CreateDate, ModifyDate)
        VALUES (@dbName, 'ERROR: ' + ERROR_MESSAGE(), 'N/A', 'N/A', GETDATE(), GETDATE());
    END CATCH

    FETCH NEXT FROM db_cursor INTO @dbName;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;

SELECT * FROM #DbUsers ORDER BY DatabaseName, UserName;

DROP TABLE #DbUsers;
