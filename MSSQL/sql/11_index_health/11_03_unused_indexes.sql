-- =============================================================================
-- Chapter:      11 — Index Health
-- Section:      11.03 — Unused Indexes
-- Checklist:    11.3
-- Min Version:  SQL Server 2016 (v13)
-- Description:  Identifies non-clustered, non-PK, non-unique-constraint
--               indexes that have zero or low read activity since last
--               SQL Server restart. Flags WRITE_ONLY and ZERO_USAGE indexes
--               for further review. Includes estimated index size in MB.
--
-- NOTE: sys.dm_db_index_usage_stats is reset every time SQL Server
-- restarts. An index that appears unused may be actively used during
-- periods not captured in the current uptime window (e.g. month-end
-- batch jobs, quarterly reports). Do NOT drop any index based solely
-- on this output. Validate usage across a FULL BUSINESS CYCLE before
-- considering removal. Primary keys, unique constraints, and indexes
-- that enforce referential integrity are excluded automatically, but
-- application code and ORM-generated queries must also be checked.
-- Never make automatic drop recommendations from this data.
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
    WHERE  state_desc  = 'ONLINE'
      AND  database_id > 4;

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
    i.is_primary_key                                   AS IsPrimaryKey,
    i.is_unique                                        AS IsUnique,
    i.is_unique_constraint                             AS IsUniqueConstraint,
    ISNULL(ius.user_seeks,   0)                        AS UserSeeks,
    ISNULL(ius.user_scans,   0)                        AS UserScans,
    ISNULL(ius.user_lookups, 0)                        AS UserLookups,
    ISNULL(ius.user_updates, 0)                        AS UserUpdates,
    ius.last_user_seek                                 AS LastUserSeek,
    ius.last_user_scan                                 AS LastUserScan,
    ius.last_user_lookup                               AS LastUserLookup,
    ius.last_user_update                               AS LastUserUpdate,
    (
        SELECT SUM(a.total_pages) * 8 / 1024
        FROM   sys.partitions p
        JOIN   sys.allocation_units a
            ON  a.container_id = p.hobt_id
        WHERE  p.object_id = i.object_id
          AND  p.index_id  = i.index_id
    )                                                  AS IndexSizeMB,
    CASE
        WHEN ISNULL(ius.user_seeks,   0) = 0
         AND ISNULL(ius.user_scans,   0) = 0
         AND ISNULL(ius.user_lookups, 0) = 0
         AND ISNULL(ius.user_updates, 0) > 0
            THEN ''WRITE_ONLY_CANDIDATE''
        WHEN ISNULL(ius.user_seeks,   0) = 0
         AND ISNULL(ius.user_scans,   0) = 0
         AND ISNULL(ius.user_lookups, 0) = 0
         AND ISNULL(ius.user_updates, 0) = 0
            THEN ''ZERO_USAGE''
        ELSE ''HAS_READS''
    END                                                AS UsageFlag
FROM sys.indexes i
JOIN sys.tables  t
    ON  t.object_id = i.object_id
JOIN sys.schemas s
    ON  s.schema_id = t.schema_id
LEFT JOIN sys.dm_db_index_usage_stats ius
    ON  ius.object_id   = i.object_id
    AND ius.index_id    = i.index_id
    AND ius.database_id = DB_ID()
WHERE i.type > 0                  -- exclude heaps
  AND i.is_primary_key      = 0   -- exclude primary keys
  AND i.is_unique_constraint = 0  -- exclude unique constraints
ORDER BY IndexSizeMB DESC;
';

    EXEC sys.sp_executesql @Sql;

    FETCH NEXT FROM db_cursor INTO @DatabaseName;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;
