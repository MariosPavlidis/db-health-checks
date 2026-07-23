-- ============================================================
-- Health Check: Ch 15 Security — 15.8 TRUSTWORTHY, CLR, and Assembly Risk
-- Checklist ref: Section 15.8
-- Min SQL version: 2016 (130)
-- ============================================================
-- Query 1: Databases with TRUSTWORTHY ON, particularly those owned by a
--           sysadmin — these can be used to escalate privileges.
-- Query 2: CLR configuration state (clr enabled, clr strict security).
--           CLR strict security (SQL 2017+ default ON) requires assemblies
--           to be signed by a trusted certificate or asymmetric key.
-- Query 3: UNSAFE and EXTERNAL_ACCESS assemblies across all online databases
--           via dynamic SQL — these require explicit trust or strict security bypass.
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- ── 1. TRUSTWORTHY databases and ownership risk ───────────────────────────────
SELECT
    d.name                                          AS DatabaseName,
    d.database_id,
    d.is_trustworthy_on                             AS IsTrustworthyOn,
    d.is_db_chaining_on                             AS IsChainedOwnership,
    sp.name                                         AS DatabaseOwner,
    sp.type_desc                                    AS OwnerType,
    -- Flag: sysadmin-owned trustworthy databases are an escalation path
    CASE
        WHEN d.is_trustworthy_on = 1
             AND IS_SRVROLEMEMBER('sysadmin', sp.name) = 1
             THEN 'TRUSTWORTHY_SYSADMIN_OWNER'
        WHEN d.is_trustworthy_on = 1
             THEN 'TRUSTWORTHY_ON'
        ELSE ''
    END                                             AS TrustworthyFlag
FROM sys.databases d
LEFT JOIN sys.server_principals sp
    ON sp.sid = d.owner_sid
WHERE d.state_desc = 'ONLINE'
  AND d.database_id > 4                            -- exclude system databases
ORDER BY d.is_trustworthy_on DESC, d.name;

-- ── 2. CLR configuration ──────────────────────────────────────────────────────
SELECT
    c.name                                          AS ConfigOption,
    CAST(c.value_in_use AS INT)                     AS ValueInUse,
    CAST(c.value AS INT)                            AS ConfiguredValue,
    c.description,
    CASE
        WHEN c.name = 'clr enabled'
             AND CAST(c.value_in_use AS INT) = 1    THEN 'CLR_ENABLED'
        WHEN c.name = 'clr strict security'
             AND CAST(c.value_in_use AS INT) = 0    THEN 'STRICT_SECURITY_DISABLED'
        ELSE ''
    END                                             AS CLRFlag
FROM sys.configurations c
WHERE c.name IN ('clr enabled', 'clr strict security')
ORDER BY c.name;

-- ── 3. UNSAFE/EXTERNAL_ACCESS assemblies across databases ─────────────────────
IF OBJECT_ID('tempdb..#AssemblyRisk') IS NOT NULL
    DROP TABLE #AssemblyRisk;

CREATE TABLE #AssemblyRisk (
    DatabaseName        NVARCHAR(128),
    AssemblyName        NVARCHAR(256),
    PermissionSet       NVARCHAR(60),
    IsUserDefined       BIT,
    CreateDate          DATETIME,
    ClrName             NVARCHAR(4000)
);

DECLARE @db  NVARCHAR(128);
DECLARE @sql NVARCHAR(MAX);

DECLARE db_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE state_desc = 'ONLINE'
      AND database_id > 4
    ORDER BY name;

OPEN db_cur;
FETCH NEXT FROM db_cur INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
    USE ' + QUOTENAME(@db) + N';
    INSERT INTO #AssemblyRisk (DatabaseName, AssemblyName, PermissionSet, IsUserDefined, CreateDate, ClrName)
    SELECT
        DB_NAME(),
        a.name,
        a.permission_set_desc,
        CASE WHEN a.principal_id IS NOT NULL THEN 1 ELSE 0 END,
        a.create_date,
        a.clr_name
    FROM sys.assemblies a
    WHERE a.permission_set_desc IN (''UNSAFE_ACCESS'', ''EXTERNAL_ACCESS'')
      AND a.is_user_defined = 1;
    ';
    BEGIN TRY EXEC sp_executesql @sql; END TRY
    BEGIN CATCH END CATCH;
    FETCH NEXT FROM db_cur INTO @db;
END

CLOSE db_cur; DEALLOCATE db_cur;

SELECT
    DatabaseName,
    AssemblyName,
    PermissionSet,
    CreateDate,
    ClrName,
    CASE PermissionSet
        WHEN 'UNSAFE_ACCESS'    THEN 'HIGH_RISK_ASSEMBLY'
        WHEN 'EXTERNAL_ACCESS'  THEN 'ELEVATED_ASSEMBLY'
        ELSE ''
    END                                             AS AssemblyRiskFlag
FROM #AssemblyRisk
ORDER BY PermissionSet DESC, DatabaseName, AssemblyName;

DROP TABLE #AssemblyRisk;
