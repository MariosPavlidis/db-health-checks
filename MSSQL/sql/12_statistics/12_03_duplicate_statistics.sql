-- =============================================================================
-- Chapter:      12 — Statistics Health
-- Section:      12.03 — Duplicate and Overlapping Statistics
-- Checklist:    12.3
-- Min Version:  SQL Server 2016 (v13)
-- Description:  Identifies statistics objects that share an identical or
--               overlapping leading column set within the same table. Compares
--               user-created and auto-created statistics only (excludes
--               system statistics). Respects filtered predicates: two
--               statistics on the same columns but different filter
--               definitions are NOT duplicates.
--
--               Two code paths based on SQL Server version:
--                 SQL 2017+ (v14+): STRING_AGG for column list aggregation
--                 SQL 2016   (v13):  FOR XML PATH fallback
--
-- NOTE: Do NOT remove duplicate statistics without first:
--   - Confirming that the query optimizer is not relying on one of the
--     statistics for a specific plan shape
--   - Checking whether filter predicates differ (even subtly)
--   - Testing execution plan stability after removal in a non-production
--     environment
--   Statistics that appear identical may produce different histograms
--   due to different sample rates or collection times.
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

WITH StatCols AS (
    SELECT
        st.object_id,
        st.stats_id,
        st.name         AS StatName,
        st.auto_created,
        st.user_created,
        CAST(
            CASE WHEN EXISTS (
                SELECT 1 FROM sys.indexes i
                WHERE  i.object_id = st.object_id
                  AND  i.name      = st.name
            ) THEN 1 ELSE 0 END
        AS BIT)         AS IsIndexStat,
        STRING_AGG(c.name, '','')
            WITHIN GROUP (ORDER BY sc.stats_column_id) AS ColumnList,
        st.filter_definition AS FilterPredicate
    FROM sys.stats st
    JOIN sys.stats_columns sc
        ON  sc.object_id = st.object_id
        AND sc.stats_id  = st.stats_id
    JOIN sys.columns c
        ON  c.object_id = sc.object_id
        AND c.column_id = sc.column_id
    WHERE st.user_created = 1
       OR st.auto_created = 1
    GROUP BY
        st.object_id, st.stats_id, st.name,
        st.auto_created, st.user_created, st.filter_definition
)
SELECT
    DB_NAME()                           AS DatabaseName,
    OBJECT_NAME(a.object_id)            AS TableName,
    a.StatName                          AS Stat1Name,
    a.IsIndexStat                       AS Stat1IsIndex,
    a.auto_created                      AS Stat1AutoCreated,
    b.StatName                          AS Stat2Name,
    b.IsIndexStat                       AS Stat2IsIndex,
    b.auto_created                      AS Stat2AutoCreated,
    a.ColumnList                        AS ColumnList,
    CASE
        WHEN a.ColumnList = b.ColumnList
         AND ISNULL(a.FilterPredicate, '''') = ISNULL(b.FilterPredicate, '''')
            THEN ''EXACT_DUPLICATE''
        ELSE ''OVERLAPPING_PREFIX''
    END                                 AS DuplicateType,
    a.FilterPredicate                   AS FilterPredicate1,
    b.FilterPredicate                   AS FilterPredicate2
FROM StatCols a
JOIN StatCols b
    ON  b.object_id = a.object_id
    AND b.stats_id  > a.stats_id
    AND b.ColumnList LIKE a.ColumnList + ''%''
ORDER BY OBJECT_NAME(a.object_id), a.StatName;
';
    END
    -- ── SQL 2016 path: FOR XML PATH fallback ──────────────────────────────────
    ELSE
    BEGIN
        SET @Sql = N'
USE ' + QUOTENAME(@DatabaseName) + N';

WITH StatCols AS (
    SELECT
        st.object_id,
        st.stats_id,
        st.name         AS StatName,
        st.auto_created,
        st.user_created,
        CAST(
            CASE WHEN EXISTS (
                SELECT 1 FROM sys.indexes i
                WHERE  i.object_id = st.object_id
                  AND  i.name      = st.name
            ) THEN 1 ELSE 0 END
        AS BIT)         AS IsIndexStat,
        STUFF((
            SELECT '','' + c2.name
            FROM   sys.stats_columns sc2
            JOIN   sys.columns c2
                ON  c2.object_id = sc2.object_id
                AND c2.column_id = sc2.column_id
            WHERE  sc2.object_id = st.object_id
              AND  sc2.stats_id  = st.stats_id
            ORDER BY sc2.stats_column_id
            FOR XML PATH(''''), TYPE
        ).value(''.'',''NVARCHAR(MAX)''), 1, 1, '''') AS ColumnList,
        st.filter_definition AS FilterPredicate
    FROM sys.stats st
    WHERE st.user_created = 1
       OR st.auto_created = 1
)
SELECT
    DB_NAME()                           AS DatabaseName,
    OBJECT_NAME(a.object_id)            AS TableName,
    a.StatName                          AS Stat1Name,
    a.IsIndexStat                       AS Stat1IsIndex,
    a.auto_created                      AS Stat1AutoCreated,
    b.StatName                          AS Stat2Name,
    b.IsIndexStat                       AS Stat2IsIndex,
    b.auto_created                      AS Stat2AutoCreated,
    a.ColumnList                        AS ColumnList,
    CASE
        WHEN a.ColumnList = b.ColumnList
         AND ISNULL(a.FilterPredicate, '''') = ISNULL(b.FilterPredicate, '''')
            THEN ''EXACT_DUPLICATE''
        ELSE ''OVERLAPPING_PREFIX''
    END                                 AS DuplicateType,
    a.FilterPredicate                   AS FilterPredicate1,
    b.FilterPredicate                   AS FilterPredicate2
FROM StatCols a
JOIN StatCols b
    ON  b.object_id = a.object_id
    AND b.stats_id  > a.stats_id
    AND b.ColumnList LIKE a.ColumnList + ''%''
ORDER BY OBJECT_NAME(a.object_id), a.StatName;
';
    END

    EXEC sys.sp_executesql @Sql;

    FETCH NEXT FROM db_cursor INTO @DatabaseName;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;
