-- =============================================================================
-- Chapter:      11 — Index Health
-- Section:      11.01 — Index Fragmentation
-- Checklist:    11.1
-- Min Version:  SQL Server 2016 (v13)
-- Description:  Collects index fragmentation data across all online user
--               databases using LIMITED scan mode. Flags indexes with
--               fragmentation above 10% or 30% where page count > 1000.
--
-- NOTE: Fragmentation alone is not sufficient justification for
-- REBUILD or REORGANIZE. Always consider page count, workload pattern,
-- fill factor, and the organization's maintenance policy before acting.
-- Small indexes (< 1000 pages) showing high fragmentation are expected
-- and typically not worth maintaining. Align actions with a documented
-- index maintenance strategy (e.g. Ola Hallengren, maintenance plans).
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

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM   sys.databases
    WHERE  state_desc   = 'ONLINE'
      AND  database_id  > 4;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @DatabaseName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @Sql = N'
USE ' + QUOTENAME(@DatabaseName) + N';

SELECT
    DB_NAME()                                          AS DatabaseName,
    s.name                                             AS SchemaName,
    t.name                                             AS TableName,
    i.name                                             AS IndexName,
    i.type_desc                                        AS IndexType,
    ips.partition_number                               AS PartitionNumber,
    ips.page_count                                     AS PageCount,
    ips.avg_fragmentation_in_percent                   AS FragmentationPct,
    ips.fragment_count                                 AS FragmentCount,
    ips.avg_fragment_size_in_pages                     AS AvgFragmentSizePages,
    i.fill_factor                                      AS [FillFactor],
    ips.alloc_unit_type_desc                           AS AllocUnitType,
    CASE
        WHEN ips.avg_fragmentation_in_percent > 30
             AND ips.page_count > 1000 THEN ''HIGH''
        WHEN ips.avg_fragmentation_in_percent > 10
             AND ips.page_count > 1000 THEN ''MEDIUM''
        ELSE ''OK''
    END                                                AS FragmentationFlag
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, ''LIMITED'') ips
JOIN sys.indexes i
    ON  i.object_id = ips.object_id
    AND i.index_id  = ips.index_id
JOIN sys.tables t
    ON  t.object_id = i.object_id
JOIN sys.schemas s
    ON  s.schema_id = t.schema_id
WHERE ips.page_count > 100   -- exclude very small indexes
  AND i.type > 0             -- exclude heaps
ORDER BY ips.avg_fragmentation_in_percent DESC;
';

    EXEC sys.sp_executesql @Sql;

    FETCH NEXT FROM db_cursor INTO @DatabaseName;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;
