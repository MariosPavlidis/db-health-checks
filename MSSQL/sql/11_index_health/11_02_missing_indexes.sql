-- =============================================================================
-- Chapter:      11 — Index Health
-- Section:      11.02 — Missing Index Recommendations
-- Checklist:    11.2
-- Min Version:  SQL Server 2016 (v13)
-- Description:  Queries the missing index DMVs across all user databases and
--               ranks recommendations by IndexAdvantage (seeks * cost * impact).
--               Also generates a ProposedIndex DDL suggestion and an
--               ExistingIndexAnalysis column that shows whether any existing
--               index already partially or fully covers the recommendation —
--               the most common reason to skip or modify a DMV suggestion.
--
--               Implementation uses two temp tables so the ExistingIndexAnalysis
--               CTE runs in plain T-SQL without deeply nested dynamic SQL:
--                 #MissingIndexes — populated from server-level DMVs (all DBs)
--                 #Indexes        — populated per-database via a cursor
--
-- NOTE: DMV-based recommendations MUST be reviewed before any index is created.
--       The DMVs do not account for write amplification, transient workloads,
--       or whether the suggested columns are already covered by another index.
--       ExistingIndexAnalysis surfaces the latter directly.
--       Counters reset on SQL Server restart or database offline.
-- =============================================================================

IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning];
    RETURN;
END
GO

SET NOCOUNT ON;

-- ── Step 1: Missing index recommendations (server-level DMVs — all user DBs) ──
IF OBJECT_ID('tempdb..#MissingIndexes') IS NOT NULL DROP TABLE #MissingIndexes;

SELECT
    CAST(SERVERPROPERTY('ServerName') AS SYSNAME)                           AS SQLServer,
    DB_NAME(id.database_id)                                                 AS DatabaseName,
    id.database_id,
    id.object_id,
    OBJECT_SCHEMA_NAME(id.object_id, id.database_id)                       AS SchemaName,
    OBJECT_NAME(id.object_id, id.database_id)                              AS TableName,
    id.[statement]                                                          AS FullyQualifiedObjectName,
    id.equality_columns,
    id.inequality_columns,
    id.included_columns,
    gs.unique_compiles                                                      AS UniqueCompiles,
    gs.user_seeks                                                           AS UserSeeks,
    gs.user_scans                                                           AS UserScans,
    gs.last_user_seek                                                       AS LastUserSeek,
    gs.last_user_scan                                                       AS LastUserScan,
    gs.avg_total_user_cost                                                  AS AvgQueryCost,
    gs.avg_user_impact                                                      AS AvgImpactPct,
    gs.user_seeks * gs.avg_total_user_cost * (gs.avg_user_impact * 0.01)   AS IndexAdvantage,
    -- Normalised key column list for matching against existing indexes
    LOWER(REPLACE(REPLACE(REPLACE(
        ISNULL(id.equality_columns, '') +
        CASE WHEN id.equality_columns   IS NOT NULL
              AND id.inequality_columns IS NOT NULL THEN ',' ELSE '' END +
        ISNULL(id.inequality_columns, ''),
    '[', ''), ']', ''), ' ', ''))                                           AS RequestedKeyColsNormalized
INTO #MissingIndexes
FROM sys.dm_db_missing_index_group_stats   AS gs
JOIN sys.dm_db_missing_index_groups        AS ig ON gs.group_handle = ig.index_group_handle
JOIN sys.dm_db_missing_index_details       AS id ON ig.index_handle = id.index_handle
WHERE id.database_id > 4;

-- ── Step 2: Existing indexes per database (cursor — needs per-DB sys.* views) ─
IF OBJECT_ID('tempdb..#Indexes') IS NOT NULL DROP TABLE #Indexes;

CREATE TABLE #Indexes
(
    database_id          INT            NOT NULL,
    object_id            INT            NOT NULL,
    index_id             INT            NOT NULL,
    IndexName            NVARCHAR(128)  NULL,
    type_desc            NVARCHAR(60)   NULL,
    is_unique            BIT            NOT NULL,
    is_primary_key       BIT            NOT NULL,
    KeyColumns           NVARCHAR(MAX)  NULL,
    IncludedColumns      NVARCHAR(MAX)  NULL,
    KeyColumnsNormalized NVARCHAR(MAX)  NULL
);

DECLARE @DbName NVARCHAR(128);
DECLARE @DbId   INT;
DECLARE @Sql    NVARCHAR(MAX);

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name, database_id
    FROM   sys.databases
    WHERE  state_desc  = 'ONLINE'
      AND  database_id > 4;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @DbName, @DbId;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- Only fetch indexes for databases that actually have missing index entries
    IF EXISTS (SELECT 1 FROM #MissingIndexes WHERE database_id = @DbId)
    BEGIN
        SET @Sql = N'
USE ' + QUOTENAME(@DbName) + N';
INSERT INTO #Indexes
    (database_id, object_id, index_id, IndexName, type_desc,
     is_unique, is_primary_key, KeyColumns, IncludedColumns, KeyColumnsNormalized)
SELECT
    ' + CAST(@DbId AS NVARCHAR(10)) + N',
    i.object_id, i.index_id, i.name, i.type_desc, i.is_unique, i.is_primary_key,
    STUFF((
        SELECT '','' + c.name
        FROM sys.index_columns ic
        JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
        WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id
          AND ic.is_included_column = 0
        ORDER BY ic.key_ordinal
        FOR XML PATH(''''), TYPE).value(''.'', ''NVARCHAR(MAX)''), 1, 1, ''''),
    ISNULL(STUFF((
        SELECT '','' + c.name
        FROM sys.index_columns ic
        JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
        WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id
          AND ic.is_included_column = 1
        ORDER BY c.column_id
        FOR XML PATH(''''), TYPE).value(''.'', ''NVARCHAR(MAX)''), 1, 1, ''''), ''''),
    LOWER(REPLACE(REPLACE(REPLACE(
        ISNULL(STUFF((
            SELECT '','' + c.name
            FROM sys.index_columns ic
            JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
            WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id
              AND ic.is_included_column = 0
            ORDER BY ic.key_ordinal
            FOR XML PATH(''''), TYPE).value(''.'', ''NVARCHAR(MAX)''), 1, 1, ''''), ''''),
        ''['', ''''), '']'', ''''), '' '', '''')))
FROM sys.indexes i
WHERE i.is_hypothetical = 0
  AND i.index_id > 0
  AND i.type IN (1, 2);';   -- clustered and nonclustered rowstore only

        EXEC sys.sp_executesql @Sql;
    END

    FETCH NEXT FROM db_cursor INTO @DbName, @DbId;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;

-- ── Step 3: Analyse and output ────────────────────────────────────────────────
;WITH MissingCols AS
(
    -- Expand the normalised missing-index key list into one row per column
    SELECT
        mi.database_id, mi.object_id, mi.RequestedKeyColsNormalized,
        x.n.value('.', 'SYSNAME') AS colname,
        ROW_NUMBER() OVER (PARTITION BY mi.database_id, mi.object_id,
                           mi.RequestedKeyColsNormalized ORDER BY (SELECT NULL)) AS key_ordinal
    FROM #MissingIndexes mi
    CROSS APPLY (SELECT TRY_CAST(
        '<r><c>' + REPLACE(mi.RequestedKeyColsNormalized, ',', '</c><c>') + '</c></r>'
        AS XML)) d(xmlval)
    CROSS APPLY d.xmlval.nodes('/r/c') x(n)
    WHERE mi.RequestedKeyColsNormalized <> ''
),
ExistingCols AS
(
    -- Expand the normalised existing-index key list into one row per column
    SELECT
        idx.database_id, idx.object_id, idx.index_id,
        x.n.value('.', 'SYSNAME') AS colname,
        ROW_NUMBER() OVER (PARTITION BY idx.database_id, idx.object_id,
                           idx.index_id ORDER BY (SELECT NULL)) AS key_ordinal
    FROM #Indexes idx
    CROSS APPLY (SELECT TRY_CAST(
        '<r><c>' + REPLACE(idx.KeyColumnsNormalized, ',', '</c><c>') + '</c></r>'
        AS XML)) d(xmlval)
    CROSS APPLY d.xmlval.nodes('/r/c') x(n)
    WHERE idx.KeyColumnsNormalized <> ''
),
MissingKeyCount AS
(
    SELECT database_id, object_id, RequestedKeyColsNormalized, COUNT(*) AS MissingKeyCount
    FROM MissingCols
    GROUP BY database_id, object_id, RequestedKeyColsNormalized
),
ExistingKeyCount AS
(
    SELECT database_id, object_id, index_id, COUNT(*) AS ExistingKeyCount
    FROM ExistingCols
    GROUP BY database_id, object_id, index_id
),
Comparison AS
(
    SELECT
        mi.database_id, mi.object_id, mi.RequestedKeyColsNormalized,
        idx.index_id, idx.IndexName, idx.type_desc, idx.is_unique, idx.is_primary_key,
        idx.KeyColumns, idx.IncludedColumns,
        mkc.MissingKeyCount, ekc.ExistingKeyCount,
        -- How many leading key columns align between the missing and existing index
        ISNULL(
            (SELECT MIN(v.key_ordinal) - 1
             FROM (SELECT ec.key_ordinal, mc.colname AS missing_col, ec.colname AS existing_col
                   FROM ExistingCols ec
                   JOIN MissingCols  mc
                       ON  mc.database_id                = mi.database_id
                       AND mc.object_id                  = mi.object_id
                       AND mc.RequestedKeyColsNormalized = mi.RequestedKeyColsNormalized
                       AND mc.key_ordinal                = ec.key_ordinal
                   WHERE ec.database_id = idx.database_id
                     AND ec.object_id   = idx.object_id
                     AND ec.index_id    = idx.index_id) v
             WHERE v.missing_col <> v.existing_col),
            CASE WHEN ekc.ExistingKeyCount <= mkc.MissingKeyCount
                 THEN ekc.ExistingKeyCount ELSE mkc.MissingKeyCount END
        ) AS PrefixMatchCount
    FROM #MissingIndexes mi
    JOIN #Indexes         idx ON  idx.database_id = mi.database_id
                              AND idx.object_id   = mi.object_id
    JOIN MissingKeyCount  mkc ON  mkc.database_id                = mi.database_id
                              AND mkc.object_id                  = mi.object_id
                              AND mkc.RequestedKeyColsNormalized = mi.RequestedKeyColsNormalized
    JOIN ExistingKeyCount ekc ON  ekc.database_id = idx.database_id
                              AND ekc.object_id   = idx.object_id
                              AND ekc.index_id    = idx.index_id
),
Classified AS
(
    SELECT c.*,
        CASE
            WHEN c.PrefixMatchCount = 0 THEN NULL
            WHEN c.PrefixMatchCount = c.MissingKeyCount
             AND c.PrefixMatchCount = c.ExistingKeyCount  THEN 'EXACT_KEY_MATCH'
            WHEN c.PrefixMatchCount = c.ExistingKeyCount
             AND c.ExistingKeyCount < c.MissingKeyCount   THEN 'EXISTING_IS_PREFIX_OF_MISSING'
            WHEN c.PrefixMatchCount = c.MissingKeyCount
             AND c.MissingKeyCount  < c.ExistingKeyCount  THEN 'MISSING_IS_PREFIX_OF_EXISTING'
            WHEN c.PrefixMatchCount = 1                   THEN 'SAME_FIRST_KEY_ONLY'
            ELSE 'PARTIAL_LEADING_MATCH'
        END AS MatchType
    FROM Comparison c
)
SELECT
    mi.SQLServer,
    mi.DatabaseName,
    mi.SchemaName,
    mi.TableName,
    mi.FullyQualifiedObjectName,
    mi.equality_columns                                                     AS EqualityColumns,
    mi.inequality_columns                                                   AS InequalityColumns,
    mi.included_columns                                                     AS IncludedColumns,
    mi.UniqueCompiles,
    mi.UserSeeks,
    mi.UserScans,
    mi.LastUserSeek,
    mi.LastUserScan,
    mi.AvgQueryCost,
    mi.AvgImpactPct,
    mi.IndexAdvantage,
    -- Ready-to-review CREATE INDEX DDL (rename before executing)
    'CREATE INDEX [IX_MI_' +
        mi.TableName + '_' +
        REPLACE(REPLACE(REPLACE(ISNULL(mi.equality_columns,   ''), ', ', '_'), '[', ''), ']', '') +
        CASE WHEN mi.equality_columns IS NOT NULL
              AND mi.inequality_columns IS NOT NULL THEN '_' ELSE '' END +
        REPLACE(REPLACE(REPLACE(ISNULL(mi.inequality_columns, ''), ', ', '_'), '[', ''), ']', '') +
        '_' + LEFT(CONVERT(VARCHAR(36), NEWID()), 5) + ']' +
        ' ON ' + mi.FullyQualifiedObjectName +
        ' (' + ISNULL(mi.equality_columns, '') +
        CASE WHEN mi.equality_columns IS NOT NULL
              AND mi.inequality_columns IS NOT NULL THEN ',' ELSE '' END +
        ISNULL(mi.inequality_columns, '') + ')' +
        CASE WHEN mi.included_columns IS NOT NULL
             THEN ' INCLUDE (' + mi.included_columns + ')' ELSE '' END     AS ProposedIndex,
    -- Existing indexes that share leading key columns with this recommendation
    ISNULL(
        STUFF((
            SELECT
                ' | ' + c.IndexName +
                ' [' + c.MatchType +
                '; ' + c.type_desc +
                CASE WHEN c.is_unique      = 1 THEN ', UQ' ELSE '' END +
                CASE WHEN c.is_primary_key = 1 THEN ', PK' ELSE '' END +
                '; prefix=' + CAST(c.PrefixMatchCount AS VARCHAR(10)) +
                '] (' + ISNULL(c.KeyColumns, '') + ')' +
                CASE WHEN ISNULL(c.IncludedColumns, '') <> ''
                     THEN ' INCLUDE (' + c.IncludedColumns + ')' ELSE '' END
            FROM Classified c
            WHERE c.database_id                = mi.database_id
              AND c.object_id                  = mi.object_id
              AND c.RequestedKeyColsNormalized = mi.RequestedKeyColsNormalized
              AND c.MatchType IS NOT NULL
            ORDER BY
                CASE c.MatchType
                    WHEN 'EXACT_KEY_MATCH'                 THEN 1
                    WHEN 'MISSING_IS_PREFIX_OF_EXISTING'   THEN 2
                    WHEN 'EXISTING_IS_PREFIX_OF_MISSING'   THEN 3
                    WHEN 'PARTIAL_LEADING_MATCH'           THEN 4
                    WHEN 'SAME_FIRST_KEY_ONLY'             THEN 5
                    ELSE 99
                END,
                c.PrefixMatchCount DESC, c.IndexName
            FOR XML PATH(''), TYPE
        ).value('.', 'NVARCHAR(MAX)'), 1, 3, ''),
        '[no relevant leading-key overlap]'
    )                                                                       AS ExistingIndexAnalysis
FROM #MissingIndexes mi
ORDER BY mi.IndexAdvantage DESC
OPTION (RECOMPILE);

-- ── Cleanup ───────────────────────────────────────────────────────────────────
IF OBJECT_ID('tempdb..#MissingIndexes') IS NOT NULL DROP TABLE #MissingIndexes;
IF OBJECT_ID('tempdb..#Indexes')        IS NOT NULL DROP TABLE #Indexes;
