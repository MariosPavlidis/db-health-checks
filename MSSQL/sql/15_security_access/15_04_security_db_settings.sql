-- ============================================================
-- Health Check: Ch 15 Security and Access — 15.4 Database Security Settings
-- Checklist ref: Section 15.4
-- Min SQL version: 2016 (130)
-- ============================================================
-- Per-database security configuration: TRUSTWORTHY, cross-database chaining,
-- containment model, CLR assembly permission sets, and database owner.
-- TRUSTWORTHY + chaining together is the highest-risk combination and is
-- flagged separately.  CLR strict security column is available in SQL 2017+.
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

SELECT
    d.name                                                  AS DatabaseName,
    d.is_trustworthy_on                                     AS IsTrustworthy,
    d.is_db_chaining_on                                     AS IsDbChaining,
    d.containment_desc                                      AS Containment,
    -- sys.assemblies has no database_id column (it is per-DB scoped);
    -- cross-database CLR assembly counts require dynamic SQL — not supported here.
    NULL                                                    AS ExternalAccessAssemblyCount,
    NULL                                                    AS UnsafeAssemblyCount,
    -- CLR strict security (introduced in SQL Server 2017)
    CASE
        WHEN CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) >= 14
        THEN (  SELECT CAST(value AS VARCHAR(10))
                FROM sys.configurations
                WHERE name = 'clr strict security' )
        ELSE 'N/A'
    END                                                     AS CLRStrictSecurity,
    SUSER_SNAME(d.owner_sid)                                AS DatabaseOwner,
    -- Risk classification: highest risk is both TRUSTWORTHY and chaining enabled
    CASE
        WHEN d.is_trustworthy_on = 1 AND d.is_db_chaining_on = 1
            THEN 'TRUST+CHAIN_RISK'
        WHEN d.is_trustworthy_on = 1
            THEN 'TRUSTWORTHY_ON'
        WHEN d.is_db_chaining_on = 1
            THEN 'DB_CHAINING_ON'
        ELSE ''
    END                                                     AS RiskFlag
FROM sys.databases d
WHERE d.database_id > 4
ORDER BY d.name;
