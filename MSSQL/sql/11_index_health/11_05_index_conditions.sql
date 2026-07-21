-- =============================================================================
-- Chapter:      11 — Index Health
-- Section:      11.05 — Index Conditions (Disabled, Hypothetical, Heaps,
--                        Compression, Misaligned, Indexed Views)
-- Checklist:    11.5
-- Min Version:  SQL Server 2016 (v13)
-- Description:  Six sub-checks per user database:
--                 1. Disabled indexes
--                 2. Hypothetical indexes (DTA/auto-tune artifacts)
--                 3. Heaps with forwarded record metrics
--                 4. Index compression settings and fill factor anomalies
--                    (includes optimize_for_sequential_key on SQL 2019+)
--                 5. Misaligned indexes (partition scheme differs from table)
--                 6. Indexed views
-- =============================================================================

IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning];
    RETURN;
END
GO

SET NOCOUNT ON;

DECLARE @DatabaseName  NVARCHAR(128);
DECLARE @Sql           NVARCHAR(MAX);
DECLARE @MajorVersion  INT = CAST(SERVERPROPERTY('ProductMajorVersion') AS INT);

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM   sys.databases
    WHERE  state_desc  = 'ONLINE'
      AND  database_id > 4;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @DatabaseName;

WHILE @@FETCH_STATUS = 0
BEGIN

    -- ── 1. Disabled indexes ───────────────────────────────────────────────────
    SET @Sql = N'
USE ' + QUOTENAME(@DatabaseName) + N';

SELECT
    DB_NAME()           AS DatabaseName,
    ''DISABLED_INDEX''  AS CheckType,
    s.name              AS SchemaName,
    t.name              AS TableName,
    i.name              AS IndexName,
    i.type_desc         AS IndexType,
    i.is_primary_key    AS IsPrimaryKey,
    i.is_unique         AS IsUnique
FROM sys.indexes i
JOIN sys.tables  t ON t.object_id = i.object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE i.is_disabled = 1
ORDER BY t.name, i.name;
';
    EXEC sys.sp_executesql @Sql;

    -- ── 2. Hypothetical indexes ───────────────────────────────────────────────
    SET @Sql = N'
USE ' + QUOTENAME(@DatabaseName) + N';

SELECT
    DB_NAME()              AS DatabaseName,
    ''HYPOTHETICAL_INDEX'' AS CheckType,
    s.name                 AS SchemaName,
    t.name                 AS TableName,
    i.name                 AS IndexName,
    i.type_desc            AS IndexType
FROM sys.indexes i
JOIN sys.tables  t ON t.object_id = i.object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE i.is_hypothetical = 1
ORDER BY t.name, i.name;
';
    EXEC sys.sp_executesql @Sql;

    -- ── 3. Heaps with forwarded record counts ─────────────────────────────────
    SET @Sql = N'
USE ' + QUOTENAME(@DatabaseName) + N';

SELECT
    DB_NAME()                                                       AS DatabaseName,
    ''HEAP''                                                        AS CheckType,
    s.name                                                          AS SchemaName,
    t.name                                                          AS TableName,
    p.rows                                                          AS [RowCount],
    ps.forwarded_record_count                                       AS ForwardedRecordCount,
    ps.page_count                                                   AS PageCount,
    CASE
        WHEN ps.forwarded_record_count > ps.page_count * 5
            THEN ''HIGH_FORWARDED''
        ELSE ''OK''
    END                                                             AS ForwardedFlag
FROM sys.tables t
JOIN sys.schemas s
    ON  s.schema_id = t.schema_id
JOIN sys.partitions p
    ON  p.object_id = t.object_id
    AND p.index_id  = 0
JOIN sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, ''DETAILED'') ps
    ON  ps.object_id = t.object_id
    AND ps.index_id  = 0
WHERE p.rows > 0
ORDER BY ps.forwarded_record_count DESC;
';
    EXEC sys.sp_executesql @Sql;

    -- ── 4. Compression, fill factor, and sequential key flag ──────────────────
    -- optimize_for_sequential_key is a SQL 2019+ column; guard with version check
    IF @MajorVersion >= 15
    BEGIN
        SET @Sql = N'
USE ' + QUOTENAME(@DatabaseName) + N';

SELECT
    DB_NAME()                                       AS DatabaseName,
    ''COMPRESSION_FILLFACTOR''                      AS CheckType,
    s.name                                          AS SchemaName,
    t.name                                          AS TableName,
    i.name                                          AS IndexName,
    i.type_desc                                     AS IndexType,
    i.fill_factor                                   AS [FillFactor],
    p.data_compression_desc                         AS CompressionType,
    i.optimize_for_sequential_key                   AS OptimizeForSequentialKey,
    CASE
        WHEN i.fill_factor NOT IN (0, 80, 85, 90) THEN ''NONSTANDARD_FILLFACTOR''
        ELSE ''OK''
    END                                             AS FillFactorFlag
FROM sys.indexes i
JOIN sys.tables     t ON t.object_id = i.object_id
JOIN sys.schemas    s ON s.schema_id = t.schema_id
JOIN sys.partitions p ON p.object_id = i.object_id AND p.index_id = i.index_id
WHERE i.type > 0
ORDER BY t.name, i.name;
';
    END
    ELSE
    BEGIN
        SET @Sql = N'
USE ' + QUOTENAME(@DatabaseName) + N';

SELECT
    DB_NAME()                                       AS DatabaseName,
    ''COMPRESSION_FILLFACTOR''                      AS CheckType,
    s.name                                          AS SchemaName,
    t.name                                          AS TableName,
    i.name                                          AS IndexName,
    i.type_desc                                     AS IndexType,
    i.fill_factor                                   AS [FillFactor],
    p.data_compression_desc                         AS CompressionType,
    NULL                                            AS OptimizeForSequentialKey,
    CASE
        WHEN i.fill_factor NOT IN (0, 80, 85, 90) THEN ''NONSTANDARD_FILLFACTOR''
        ELSE ''OK''
    END                                             AS FillFactorFlag
FROM sys.indexes i
JOIN sys.tables     t ON t.object_id = i.object_id
JOIN sys.schemas    s ON s.schema_id = t.schema_id
JOIN sys.partitions p ON p.object_id = i.object_id AND p.index_id = i.index_id
WHERE i.type > 0
ORDER BY t.name, i.name;
';
    END
    EXEC sys.sp_executesql @Sql;

    -- ── 5. Misaligned indexes ─────────────────────────────────────────────────
    -- An index is misaligned when its data_space_id differs from the clustered
    -- index (or heap) data_space_id of the same table.
    SET @Sql = N'
USE ' + QUOTENAME(@DatabaseName) + N';

SELECT
    DB_NAME()                AS DatabaseName,
    ''MISALIGNED_INDEX''     AS CheckType,
    s.name                   AS SchemaName,
    t.name                   AS TableName,
    i.name                   AS IndexName,
    i.type_desc              AS IndexType,
    i.data_space_id          AS IndexDataSpaceId,
    base.data_space_id       AS TableDataSpaceId,
    ds_idx.name              AS IndexFilegroup,
    ds_tbl.name              AS TableFilegroup
FROM sys.indexes i
JOIN sys.tables  t ON t.object_id = i.object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
-- Get the base data_space_id (clustered index or heap = index type 0 or 1, lowest index_id)
JOIN (
    SELECT object_id, MIN(index_id) AS base_index_id,
           data_space_id
    FROM   sys.indexes
    WHERE  type IN (0, 1)
    GROUP BY object_id, data_space_id
) base ON base.object_id = i.object_id
JOIN sys.data_spaces ds_idx ON ds_idx.data_space_id = i.data_space_id
JOIN sys.data_spaces ds_tbl ON ds_tbl.data_space_id = base.data_space_id
WHERE i.type > 1                               -- non-clustered only
  AND i.data_space_id <> base.data_space_id    -- mismatch
ORDER BY t.name, i.name;
';
    EXEC sys.sp_executesql @Sql;

    -- ── 6. Indexed views ──────────────────────────────────────────────────────
    SET @Sql = N'
USE ' + QUOTENAME(@DatabaseName) + N';

SELECT
    DB_NAME()               AS DatabaseName,
    ''INDEXED_VIEW''        AS CheckType,
    s.name                  AS SchemaName,
    v.name                  AS ViewName,
    i.name                  AS IndexName,
    i.type_desc             AS IndexType,
    i.is_unique             AS IsUnique,
    i.is_primary_key        AS IsPrimaryKey,
    sm.is_schema_bound      AS IsSchemaBound
FROM sys.views   v
JOIN sys.schemas    s  ON s.schema_id  = v.schema_id
JOIN sys.indexes    i  ON i.object_id  = v.object_id
LEFT JOIN sys.sql_modules sm ON sm.object_id = v.object_id
WHERE i.type > 0
ORDER BY v.name, i.name;
';
    EXEC sys.sp_executesql @Sql;

    FETCH NEXT FROM db_cursor INTO @DatabaseName;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;
