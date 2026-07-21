-- ============================================================
-- Health Check: Ch 04 Database Inventory — 4.4 Ownership and Collation
-- Checklist ref: Section 4.4
-- Min SQL version: 2016 (130)
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- ── Result set 1: Database ownership issues ───────────────────────────────────
-- Flags:
--   PersonalOwner      — owner does not match well-known service accounts
--   DisabledOwner      — owner login exists but is disabled in sys.server_principals
--   OrphanedOwner      — owner SID has no matching login at all
SELECT
    d.database_id                                               AS [DatabaseId],
    d.name                                                      AS [DatabaseName],
    SUSER_SNAME(d.owner_sid)                                    AS [OwnerName],
    sp.name                                                     AS [LoginName],
    sp.is_disabled                                              AS [IsLoginDisabled],
    sp.type_desc                                                AS [LoginType],
    -- Owner pattern checks
    CASE
        WHEN SUSER_SNAME(d.owner_sid) IS NULL
            THEN 1 ELSE 0
    END                                                         AS [IsOrphanedOwner],
    CASE
        WHEN sp.is_disabled = 1
            THEN 1 ELSE 0
    END                                                         AS [IsOwnerLoginDisabled],
    CASE
        WHEN SUSER_SNAME(d.owner_sid) IS NOT NULL
         AND sp.is_disabled = 0
         AND SUSER_SNAME(d.owner_sid) NOT IN ('sa')
         AND SUSER_SNAME(d.owner_sid) NOT LIKE 'NT AUTHORITY\%'
         AND SUSER_SNAME(d.owner_sid) NOT LIKE 'NT SERVICE\%'
         AND SUSER_SNAME(d.owner_sid) NOT LIKE 'BUILTIN\%'
            THEN 1 ELSE 0
    END                                                         AS [IsPotentialPersonalOwner],
    CASE
        WHEN SUSER_SNAME(d.owner_sid) IS NULL
            THEN 'Orphaned owner SID — login no longer exists'
        WHEN sp.is_disabled = 1
            THEN 'Owner login is disabled'
        WHEN SUSER_SNAME(d.owner_sid) NOT IN ('sa')
         AND SUSER_SNAME(d.owner_sid) NOT LIKE 'NT AUTHORITY\%'
         AND SUSER_SNAME(d.owner_sid) NOT LIKE 'NT SERVICE\%'
         AND SUSER_SNAME(d.owner_sid) NOT LIKE 'BUILTIN\%'
            THEN 'Owner may be a personal account — consider reassigning to sa or a service login'
        ELSE 'OK'
    END                                                         AS [OwnershipFlag]
FROM sys.databases d
LEFT JOIN sys.server_principals sp
    ON sp.sid = d.owner_sid
ORDER BY d.name;

GO

-- ── Result set 2: Database collation vs server collation ─────────────────────
DECLARE @serverCollation SYSNAME = CAST(SERVERPROPERTY('Collation') AS SYSNAME);

SELECT
    d.database_id                                               AS [DatabaseId],
    d.name                                                      AS [DatabaseName],
    d.collation_name                                            AS [DatabaseCollation],
    @serverCollation                                            AS [ServerCollation],
    CASE
        WHEN d.collation_name <> @serverCollation
            THEN 1 ELSE 0
    END                                                         AS [CollationMismatch],
    CASE
        WHEN d.collation_name <> @serverCollation
            THEN 'Database collation differs from server collation — may cause implicit conversion issues'
        ELSE 'OK'
    END                                                         AS [CollationFlag]
FROM sys.databases d
ORDER BY d.name;

GO

-- ── Result set 3: Non-standard compatibility levels ───────────────────────────
-- The "latest supported" compatibility level for this SQL Server version is
-- derived from the product major version number.
-- SQL 2016 = 130, SQL 2017 = 140, SQL 2019 = 150, SQL 2022 = 160.
DECLARE @majorVer    INT   = CAST(SERVERPROPERTY('ProductMajorVersion') AS INT);
DECLARE @latestCL    TINYINT;

SET @latestCL = CASE @majorVer
    WHEN 13 THEN 130    -- SQL 2016
    WHEN 14 THEN 140    -- SQL 2017
    WHEN 15 THEN 150    -- SQL 2019
    WHEN 16 THEN 160    -- SQL 2022
    ELSE CAST(@majorVer * 10 AS TINYINT)
END;

SELECT
    d.database_id                                               AS [DatabaseId],
    d.name                                                      AS [DatabaseName],
    d.compatibility_level                                       AS [CompatibilityLevel],
    @latestCL                                                   AS [LatestSupportedLevel],
    CASE
        WHEN d.compatibility_level < @latestCL
            THEN 1 ELSE 0
    END                                                         AS [IsBelowLatest],
    CASE
        WHEN d.compatibility_level < @latestCL
            THEN 'Compat level ' + CAST(d.compatibility_level AS VARCHAR(5))
               + ' is below the latest supported level (' + CAST(@latestCL AS VARCHAR(5)) + ')'
               + ' — review CE and QO impacts before upgrading'
        ELSE 'OK'
    END                                                         AS [CompatLevelFlag]
FROM sys.databases d
WHERE d.database_id > 4   -- user databases only
ORDER BY d.name;

GO

-- ── Result set 4: FULL recovery databases with potential missing log backups ──
-- Flags databases in FULL recovery model whose log reuse is being blocked by
-- LOG_BACKUP, suggesting no log backup has been taken since the last full.
-- Correlation with Chapter 13 (backup history) is recommended.
SELECT
    d.database_id                                               AS [DatabaseId],
    d.name                                                      AS [DatabaseName],
    d.recovery_model_desc                                       AS [RecoveryModelDesc],
    d.log_reuse_wait_desc                                       AS [LogReuseWaitDesc],
    CASE
        WHEN d.recovery_model_desc = 'FULL'
         AND d.log_reuse_wait_desc = 'LOG_BACKUP'
            THEN 1 ELSE 0
    END                                                         AS [MissingLogBackupFlag],
    CASE
        WHEN d.recovery_model_desc = 'FULL'
         AND d.log_reuse_wait_desc = 'LOG_BACKUP'
            THEN 'FULL recovery model but log reuse is blocked by LOG_BACKUP '
               + '— ensure regular log backups are scheduled. Cross-reference Ch 13.'
        ELSE 'OK'
    END                                                         AS [LogBackupFlag]
FROM sys.databases d
WHERE d.database_id > 4   -- user databases only
  AND d.recovery_model_desc = 'FULL'
ORDER BY d.name;
