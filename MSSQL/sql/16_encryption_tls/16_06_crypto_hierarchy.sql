-- ============================================================
-- Health Check: Ch 16 Encryption, TLS — 16.6 Cryptographic Hierarchy
-- Checklist ref: Section 16.6
-- Min SQL version: 2016 (130)
-- ============================================================
-- Query 1: Service Master Key (SMK) — instance-level root of the crypto hierarchy.
-- Query 2: Database Master Keys (DMK) across all online databases — creation date,
--           encrypted_by info, and flag for DMKs not encrypted by SMK (offline
--           backup-only, cannot be auto-opened by SQL Server).
-- Query 3: Certificates per database — thumbprint, expiry, issuer, private-key
--           encryption type, and expiry proximity flags.
-- Query 4: Asymmetric keys per database — algorithm and key-length summary.
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- ── 1. Service Master Key ─────────────────────────────────────────────────────
SELECT
    sk.name                                         AS KeyName,
    sk.algorithm_desc                               AS Algorithm,
    sk.key_length                                   AS KeyLengthBits,
    sk.create_date                                  AS CreateDate,
    sk.modify_date                                  AS ModifyDate,
    'master'                                        AS DatabaseName
FROM master.sys.symmetric_keys sk
WHERE sk.name = '##MS_ServiceMasterKey##';

-- ── 2. Database Master Keys across all online databases ───────────────────────
IF OBJECT_ID('tempdb..#DMKInventory') IS NOT NULL DROP TABLE #DMKInventory;

CREATE TABLE #DMKInventory (
    DatabaseName        NVARCHAR(128),
    KeyName             NVARCHAR(128),
    Algorithm           NVARCHAR(60),
    KeyLengthBits       INT,
    CreateDate          DATETIME,
    ModifyDate          DATETIME,
    IsEncryptedByServer BIT,     -- 1 = encrypted by SMK (auto-open), 0 = password-only
    ModifiedBy          NVARCHAR(128)
);

DECLARE @db  NVARCHAR(128);
DECLARE @sql NVARCHAR(MAX);

DECLARE dmk_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE state_desc = 'ONLINE'
    ORDER BY name;

OPEN dmk_cur;
FETCH NEXT FROM dmk_cur INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
    USE ' + QUOTENAME(@db) + N';
    INSERT INTO #DMKInventory
    SELECT
        DB_NAME(),
        sk.name,
        sk.algorithm_desc,
        sk.key_length,
        sk.create_date,
        sk.modify_date,
        -- is_master_key_encrypted_by_server: 1 means SMK can auto-open it
        (SELECT TOP 1 d.is_master_key_encrypted_by_server
         FROM sys.databases d WHERE d.database_id = DB_ID()),
        SUSER_SNAME(sk.modify_date)   -- best available; may be NULL
    FROM sys.symmetric_keys sk
    WHERE sk.name = ''##MS_DatabaseMasterKey##'';
    ';
    BEGIN TRY EXEC sp_executesql @sql; END TRY
    BEGIN CATCH END CATCH;
    FETCH NEXT FROM dmk_cur INTO @db;
END
CLOSE dmk_cur; DEALLOCATE dmk_cur;

SELECT
    DatabaseName,
    KeyName,
    Algorithm,
    KeyLengthBits,
    CreateDate,
    ModifyDate,
    IsEncryptedByServer,
    CASE
        WHEN IsEncryptedByServer = 0 THEN 'DMK_NOT_SMK_ENCRYPTED'
        ELSE ''
    END                                             AS DMKFlag
FROM #DMKInventory
ORDER BY DatabaseName;

DROP TABLE #DMKInventory;

-- ── 3. Certificates per database ──────────────────────────────────────────────
IF OBJECT_ID('tempdb..#CertInventory') IS NOT NULL DROP TABLE #CertInventory;

CREATE TABLE #CertInventory (
    DatabaseName        NVARCHAR(128),
    CertName            NVARCHAR(128),
    Subject             NVARCHAR(256),
    Issuer              NVARCHAR(256),
    ValidFrom           DATETIME,
    ValidTo             DATETIME,
    DaysUntilExpiry     INT,
    PrivKeyEncType      NVARCHAR(60),
    Thumbprint          VARBINARY(64)
);

DECLARE cert_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE state_desc = 'ONLINE'
    ORDER BY name;

OPEN cert_cur;
FETCH NEXT FROM cert_cur INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
    USE ' + QUOTENAME(@db) + N';
    INSERT INTO #CertInventory
    SELECT
        DB_NAME(),
        c.name,
        c.subject,
        c.issuer_name,
        c.start_date,
        c.expiry_date,
        DATEDIFF(DAY, GETDATE(), c.expiry_date),
        c.pvt_key_encryption_type_desc,
        c.thumbprint
    FROM sys.certificates c
    WHERE c.name NOT LIKE ''##%##'';   -- exclude internal service certs
    ';
    BEGIN TRY EXEC sp_executesql @sql; END TRY
    BEGIN CATCH END CATCH;
    FETCH NEXT FROM cert_cur INTO @db;
END
CLOSE cert_cur; DEALLOCATE cert_cur;

SELECT
    DatabaseName,
    CertName,
    Subject,
    Issuer,
    ValidFrom,
    ValidTo,
    DaysUntilExpiry,
    PrivKeyEncType,
    CASE
        WHEN ValidTo   < GETDATE()                 THEN 'EXPIRED'
        WHEN DaysUntilExpiry < 30                  THEN 'EXPIRY_CRITICAL'
        WHEN DaysUntilExpiry < 90                  THEN 'EXPIRY_HIGH'
        WHEN DaysUntilExpiry < 180                 THEN 'EXPIRY_WARN'
        ELSE ''
    END                                             AS CertExpiryFlag
FROM #CertInventory
ORDER BY DaysUntilExpiry, DatabaseName, CertName;

DROP TABLE #CertInventory;

-- ── 4. Asymmetric keys per database ───────────────────────────────────────────
IF OBJECT_ID('tempdb..#AsymKeyInventory') IS NOT NULL DROP TABLE #AsymKeyInventory;

CREATE TABLE #AsymKeyInventory (
    DatabaseName        NVARCHAR(128),
    KeyName             NVARCHAR(128),
    Algorithm           NVARCHAR(60),
    KeyLengthBits       INT,
    ProviderType        NVARCHAR(60),
    CreateDate          DATETIME
);

DECLARE akey_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE state_desc = 'ONLINE'
    ORDER BY name;

OPEN akey_cur;
FETCH NEXT FROM akey_cur INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
    USE ' + QUOTENAME(@db) + N';
    INSERT INTO #AsymKeyInventory
    SELECT
        DB_NAME(),
        ak.name,
        ak.algorithm_desc,
        ak.key_length,
        ak.provider_type,
        ak.create_date
    FROM sys.asymmetric_keys ak
    WHERE ak.name NOT LIKE ''##%##'';
    ';
    BEGIN TRY EXEC sp_executesql @sql; END TRY
    BEGIN CATCH END CATCH;
    FETCH NEXT FROM akey_cur INTO @db;
END
CLOSE akey_cur; DEALLOCATE akey_cur;

SELECT * FROM #AsymKeyInventory ORDER BY DatabaseName, KeyName;
DROP TABLE #AsymKeyInventory;
