-- ============================================================
-- Health Check: Ch 16 Encryption, TLS — 16.7 Always Encrypted Key Metadata
-- Checklist ref: Section 16.7
-- Min SQL version: 2016 (130)
-- ============================================================
-- Query 1: Column Master Key (CMK) metadata per database — key store provider,
--           key path, and whether enclave computations are allowed.
-- Query 2: Column Encryption Key (CEK) inventory per database — algorithm, and
--           the CMK used to protect each CEK value.
-- Query 3: Encrypted columns per database — table, column, encryption type
--           (DETERMINISTIC vs RANDOMIZED) and algorithm.
-- Note: Key material (actual key values) is never exposed by these DMVs.
--       This script reports metadata only. Certificate expiry for CMKs backed
--       by Windows Certificate Store must be verified via the certificate MMC
--       snap-in or PKI tooling — SQL Server does not surface CMK expiry dates.
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- ── 1. Column Master Keys ─────────────────────────────────────────────────────
IF OBJECT_ID('tempdb..#AECMKs') IS NOT NULL DROP TABLE #AECMKs;

CREATE TABLE #AECMKs (
    DatabaseName            NVARCHAR(128),
    CMKName                 NVARCHAR(128),
    KeyStoreProviderName    NVARCHAR(256),
    KeyPath                 NVARCHAR(MAX),
    AllowEnclaveComputations BIT,
    CreateDate              DATETIME,
    ModifyDate              DATETIME
);

DECLARE @db  NVARCHAR(128);
DECLARE @sql NVARCHAR(MAX);

DECLARE cmk_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE state_desc = 'ONLINE' AND database_id > 4
    ORDER BY name;

OPEN cmk_cur;
FETCH NEXT FROM cmk_cur INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
    USE ' + QUOTENAME(@db) + N';
    INSERT INTO #AECMKs
    SELECT
        DB_NAME(),
        cmk.name,
        cmk.key_store_provider_name,
        cmk.key_path,
        cmk.allow_enclave_computations,
        cmk.create_date,
        cmk.modify_date
    FROM sys.column_master_keys cmk;
    ';
    BEGIN TRY EXEC sp_executesql @sql; END TRY
    BEGIN CATCH END CATCH;
    FETCH NEXT FROM cmk_cur INTO @db;
END
CLOSE cmk_cur; DEALLOCATE cmk_cur;

SELECT
    DatabaseName,
    CMKName,
    KeyStoreProviderName,
    KeyPath,
    AllowEnclaveComputations,
    CreateDate,
    ModifyDate
FROM #AECMKs
ORDER BY DatabaseName, CMKName;
DROP TABLE #AECMKs;

-- ── 2. Column Encryption Keys ─────────────────────────────────────────────────
IF OBJECT_ID('tempdb..#AECEKs') IS NOT NULL DROP TABLE #AECEKs;

CREATE TABLE #AECEKs (
    DatabaseName    NVARCHAR(128),
    CEKName         NVARCHAR(128),
    CMKName         NVARCHAR(128),
    Algorithm       NVARCHAR(256),
    CreateDate      DATETIME,
    ModifyDate      DATETIME
);

DECLARE cek_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE state_desc = 'ONLINE' AND database_id > 4
    ORDER BY name;

OPEN cek_cur;
FETCH NEXT FROM cek_cur INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
    USE ' + QUOTENAME(@db) + N';
    INSERT INTO #AECEKs
    SELECT
        DB_NAME(),
        cek.name,
        cmk.name,
        cekv.encryption_algorithm_name,
        cek.create_date,
        cek.modify_date
    FROM sys.column_encryption_keys cek
    JOIN sys.column_encryption_key_values cekv
        ON cekv.column_encryption_key_id = cek.column_encryption_key_id
    JOIN sys.column_master_keys cmk
        ON cmk.column_master_key_id = cekv.column_master_key_id;
    ';
    BEGIN TRY EXEC sp_executesql @sql; END TRY
    BEGIN CATCH END CATCH;
    FETCH NEXT FROM cek_cur INTO @db;
END
CLOSE cek_cur; DEALLOCATE cek_cur;

SELECT * FROM #AECEKs ORDER BY DatabaseName, CEKName;
DROP TABLE #AECEKs;

-- ── 3. Encrypted columns ──────────────────────────────────────────────────────
IF OBJECT_ID('tempdb..#AEColumns') IS NOT NULL DROP TABLE #AEColumns;

CREATE TABLE #AEColumns (
    DatabaseName        NVARCHAR(128),
    SchemaName          NVARCHAR(128),
    TableName           NVARCHAR(128),
    ColumnName          NVARCHAR(128),
    DataType            NVARCHAR(128),
    EncryptionType      NVARCHAR(64),
    EncryptionAlgorithm NVARCHAR(256),
    CEKName             NVARCHAR(128)
);

DECLARE ec_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE state_desc = 'ONLINE' AND database_id > 4
    ORDER BY name;

OPEN ec_cur;
FETCH NEXT FROM ec_cur INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
    USE ' + QUOTENAME(@db) + N';
    INSERT INTO #AEColumns
    SELECT
        DB_NAME(),
        SCHEMA_NAME(t.schema_id),
        t.name,
        c.name,
        tp.name,
        c.encryption_type_desc,
        c.encryption_algorithm_name,
        cek.name
    FROM sys.columns c
    JOIN sys.tables t
        ON t.object_id = c.object_id
    JOIN sys.types tp
        ON tp.user_type_id = c.user_type_id
    LEFT JOIN sys.column_encryption_keys cek
        ON cek.column_encryption_key_id = c.column_encryption_key_id
    WHERE c.encryption_type IS NOT NULL;
    ';
    BEGIN TRY EXEC sp_executesql @sql; END TRY
    BEGIN CATCH END CATCH;
    FETCH NEXT FROM ec_cur INTO @db;
END
CLOSE ec_cur; DEALLOCATE ec_cur;

SELECT * FROM #AEColumns ORDER BY DatabaseName, SchemaName, TableName, ColumnName;
DROP TABLE #AEColumns;
