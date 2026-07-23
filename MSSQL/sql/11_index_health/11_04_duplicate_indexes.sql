-- =============================================================================
-- Chapter:      11 — Index Health
-- Section:      11.04 — Duplicate and Overlapping Indexes
-- Checklist:    11.4
-- Min Version:  SQL Server 2016 (v13)
-- Description:  Identifies exact duplicate indexes (same key columns, same
--               included columns, same filter predicate) and prefix overlaps
--               (one index key list is a leading prefix of another) within
--               each online user database.
--
--               Two code paths are used based on SQL Server version:
--                 SQL 2017+ (v14+): STRING_AGG for column list aggregation
--                 SQL 2016   (v13):  FOR XML PATH fallback
--
-- NOTE: Do NOT consolidate or drop indexes without first:
--   - Validating all application queries and ORM-generated SQL that
--     reference the candidate indexes
--   - Reviewing actual execution plans for affected queries
--   - Checking whether one index enforces a constraint the other does not
--   - Confirming that removing an index will not break a covering plan
-- Exact duplicates are strong candidates for consolidation, but prefix
-- overlaps require careful analysis of included columns and selectivity.
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
    -- ── SQL 2017+ path: STRING_AGG ────────────────────────────────────────────
    IF @MajorVersion >= 14
    BEGIN
        SET @Sql = N'
USE ' + QUOTENAME(@DatabaseName) + N';

WITH IndexCols AS (
    SELECT
        i.object_id,
        i.index_id,
        i.name                  AS IndexName,
        i.type_desc,
        i.is_unique,
        i.is_primary_key,
        i.is_unique_constraint,
        i.filter_definition     AS FilterPredicate,
        STRING_AGG(
            CASE WHEN ic.is_included_column = 0
                 THEN c.name + '':'' + CASE ic.is_descending_key WHEN 0 THEN ''ASC'' ELSE ''DESC'' END
                 ELSE NULL END,
            '',''
        ) WITHIN GROUP (ORDER BY ic.index_column_id)   AS KeyCols,
        STRING_AGG(
            CASE WHEN ic.is_included_column = 1 THEN c.name ELSE NULL END,
            '',''
        ) WITHIN GROUP (ORDER BY ic.index_column_id)   AS IncludeCols
    FROM sys.indexes       i
    JOIN sys.index_columns ic
        ON  ic.object_id = i.object_id
        AND ic.index_id  = i.index_id
    JOIN sys.columns c
        ON  c.object_id  = ic.object_id
        AND c.column_id  = ic.column_id
    WHERE i.type > 0
    GROUP BY
        i.object_id, i.index_id, i.name, i.type_desc,
        i.is_unique, i.is_primary_key, i.is_unique_constraint, i.filter_definition
),
Pairs AS (
    SELECT
        DB_NAME()                                                           AS DatabaseName,
        OBJECT_SCHEMA_NAME(a.object_id) + ''.'' + OBJECT_NAME(a.object_id) AS TableName,
        a.IndexName                         AS Index1Name,
        a.KeyCols                           AS Index1KeyCols,
        a.IncludeCols                       AS Index1IncludeCols,
        a.is_primary_key                    AS Index1IsPK,
        a.is_unique                         AS Index1IsUnique,
        b.IndexName                         AS Index2Name,
        b.KeyCols                           AS Index2KeyCols,
        b.IncludeCols                       AS Index2IncludeCols,
        b.is_primary_key                    AS Index2IsPK,
        b.is_unique                         AS Index2IsUnique,
        CASE
            WHEN a.KeyCols = b.KeyCols
             AND ISNULL(a.IncludeCols,    '''') = ISNULL(b.IncludeCols,    '''')
             AND ISNULL(a.FilterPredicate,'''') = ISNULL(b.FilterPredicate,'''')
                THEN ''EXACT_DUPLICATE''
            WHEN b.KeyCols LIKE a.KeyCols + '',%''
                THEN ''INDEX1_IS_PREFIX''
            WHEN a.KeyCols LIKE b.KeyCols + '',%''
                THEN ''INDEX2_IS_PREFIX''
        END                                 AS DuplicateType
    FROM IndexCols a
    JOIN IndexCols b
        ON  b.object_id = a.object_id
        AND b.index_id  > a.index_id
        AND (
                a.KeyCols = b.KeyCols
             OR b.KeyCols LIKE a.KeyCols + '',%''
             OR a.KeyCols LIKE b.KeyCols + '',%''
            )
)
SELECT * FROM Pairs
WHERE  DuplicateType IS NOT NULL
ORDER BY TableName, DuplicateType;
';
    END
    -- ── SQL 2016 path: FOR XML PATH fallback ──────────────────────────────────
    ELSE
    BEGIN
        SET @Sql = N'
USE ' + QUOTENAME(@DatabaseName) + N';

WITH IndexCols AS (
    SELECT
        i.object_id,
        i.index_id,
        i.name                  AS IndexName,
        i.type_desc,
        i.is_unique,
        i.is_primary_key,
        i.is_unique_constraint,
        i.filter_definition     AS FilterPredicate,
        STUFF((
            SELECT '','' + c2.name + '':''
                       + CASE ic2.is_descending_key WHEN 0 THEN ''ASC'' ELSE ''DESC'' END
            FROM   sys.index_columns ic2
            JOIN   sys.columns       c2
                ON  c2.object_id = ic2.object_id
                AND c2.column_id = ic2.column_id
            WHERE  ic2.object_id          = i.object_id
              AND  ic2.index_id           = i.index_id
              AND  ic2.is_included_column = 0
            ORDER BY ic2.key_ordinal
            FOR XML PATH(''''), TYPE
        ).value(''.'',''NVARCHAR(MAX)''), 1, 1, '''')  AS KeyCols,
        STUFF((
            SELECT '','' + c2.name
            FROM   sys.index_columns ic2
            JOIN   sys.columns       c2
                ON  c2.object_id = ic2.object_id
                AND c2.column_id = ic2.column_id
            WHERE  ic2.object_id          = i.object_id
              AND  ic2.index_id           = i.index_id
              AND  ic2.is_included_column = 1
            ORDER BY ic2.index_column_id
            FOR XML PATH(''''), TYPE
        ).value(''.'',''NVARCHAR(MAX)''), 1, 1, '''')  AS IncludeCols
    FROM sys.indexes i
    WHERE i.type > 0
),
Pairs AS (
    SELECT
        DB_NAME()                                                           AS DatabaseName,
        OBJECT_SCHEMA_NAME(a.object_id) + ''.'' + OBJECT_NAME(a.object_id) AS TableName,
        a.IndexName                         AS Index1Name,
        a.KeyCols                           AS Index1KeyCols,
        a.IncludeCols                       AS Index1IncludeCols,
        a.is_primary_key                    AS Index1IsPK,
        a.is_unique                         AS Index1IsUnique,
        b.IndexName                         AS Index2Name,
        b.KeyCols                           AS Index2KeyCols,
        b.IncludeCols                       AS Index2IncludeCols,
        b.is_primary_key                    AS Index2IsPK,
        b.is_unique                         AS Index2IsUnique,
        CASE
            WHEN a.KeyCols = b.KeyCols
             AND ISNULL(a.IncludeCols,    '''') = ISNULL(b.IncludeCols,    '''')
             AND ISNULL(a.FilterPredicate,'''') = ISNULL(b.FilterPredicate,'''')
                THEN ''EXACT_DUPLICATE''
            WHEN b.KeyCols LIKE a.KeyCols + '',%''
                THEN ''INDEX1_IS_PREFIX''
            WHEN a.KeyCols LIKE b.KeyCols + '',%''
                THEN ''INDEX2_IS_PREFIX''
        END                                 AS DuplicateType
    FROM IndexCols a
    JOIN IndexCols b
        ON  b.object_id = a.object_id
        AND b.index_id  > a.index_id
        AND (
                a.KeyCols = b.KeyCols
             OR b.KeyCols LIKE a.KeyCols + '',%''
             OR a.KeyCols LIKE b.KeyCols + '',%''
            )
)
SELECT * FROM Pairs
WHERE  DuplicateType IS NOT NULL
ORDER BY TableName, DuplicateType;
';
    END

    EXEC sys.sp_executesql @Sql;

    FETCH NEXT FROM db_cursor INTO @DatabaseName;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;
