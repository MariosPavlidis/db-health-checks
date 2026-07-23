-- ============================================================
-- Health Check: Ch 15 Security — 15.9 Row-Level Security and Dynamic Data Masking
-- Checklist ref: Section 15.9
-- Min SQL version: 2016 (130) — RLS added in 2016; DDM added in 2016
-- ============================================================
-- Query 1: Row-Level Security policies across all online user databases.
--           Reports policy name, target schema/table, predicate type, and state.
-- Query 2: Dynamic Data Masking — masked columns per database with masking
--           function and schema/table/column details.
-- Returns no rows in either query if no RLS policies or masked columns exist.
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- ── 1. Row-Level Security policies ───────────────────────────────────────────
IF OBJECT_ID('tempdb..#RLSPolicies') IS NOT NULL DROP TABLE #RLSPolicies;

CREATE TABLE #RLSPolicies (
    DatabaseName        NVARCHAR(128),
    PolicyName          NVARCHAR(128),
    PolicySchema        NVARCHAR(128),
    IsEnabled           BIT,
    IsSchemabound       BIT,
    PredicateType       NVARCHAR(60),
    TargetSchema        NVARCHAR(128),
    TargetTable         NVARCHAR(128),
    PredicateFunction   NVARCHAR(256)
);

DECLARE @db  NVARCHAR(128);
DECLARE @sql NVARCHAR(MAX);

DECLARE rls_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE state_desc = 'ONLINE' AND database_id > 4
    ORDER BY name;

OPEN rls_cur;
FETCH NEXT FROM rls_cur INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
    USE ' + QUOTENAME(@db) + N';
    INSERT INTO #RLSPolicies
    SELECT
        DB_NAME(),
        sp.name,
        SCHEMA_NAME(sp.schema_id),
        sp.is_enabled,
        sp.is_schema_bound,
        spp.predicate_type_desc,
        SCHEMA_NAME(t.schema_id),
        t.name,
        OBJECT_NAME(spp.tvf_object_id)
    FROM sys.security_policies sp
    JOIN sys.security_predicates spp ON spp.object_id = sp.object_id
    JOIN sys.tables t ON t.object_id = spp.target_object_id;
    ';
    BEGIN TRY EXEC sp_executesql @sql; END TRY
    BEGIN CATCH END CATCH;
    FETCH NEXT FROM rls_cur INTO @db;
END
CLOSE rls_cur; DEALLOCATE rls_cur;

SELECT * FROM #RLSPolicies ORDER BY DatabaseName, PolicyName;
DROP TABLE #RLSPolicies;

-- ── 2. Dynamic Data Masking — masked columns ──────────────────────────────────
IF OBJECT_ID('tempdb..#MaskedColumns') IS NOT NULL DROP TABLE #MaskedColumns;

CREATE TABLE #MaskedColumns (
    DatabaseName        NVARCHAR(128),
    SchemaName          NVARCHAR(128),
    TableName           NVARCHAR(128),
    ColumnName          NVARCHAR(128),
    DataType            NVARCHAR(128),
    MaskingFunction     NVARCHAR(MAX)
);

DECLARE ddm_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE state_desc = 'ONLINE' AND database_id > 4
    ORDER BY name;

OPEN ddm_cur;
FETCH NEXT FROM ddm_cur INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
    USE ' + QUOTENAME(@db) + N';
    INSERT INTO #MaskedColumns
    SELECT
        DB_NAME(),
        SCHEMA_NAME(t.schema_id),
        t.name,
        c.name,
        tp.name,
        c.masking_function
    FROM sys.masked_columns c
    JOIN sys.tables t  ON t.object_id = c.object_id
    JOIN sys.types  tp ON tp.user_type_id = c.user_type_id
    WHERE c.is_masked = 1;
    ';
    BEGIN TRY EXEC sp_executesql @sql; END TRY
    BEGIN CATCH END CATCH;
    FETCH NEXT FROM ddm_cur INTO @db;
END
CLOSE ddm_cur; DEALLOCATE ddm_cur;

SELECT * FROM #MaskedColumns ORDER BY DatabaseName, SchemaName, TableName, ColumnName;
DROP TABLE #MaskedColumns;
