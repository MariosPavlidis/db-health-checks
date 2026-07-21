-- =============================================================================
-- Chapter:      12 — Statistics Health
-- Section:      12.01 — Statistics Inventory
-- Checklist:    12.1
-- Min Version:  SQL Server 2016 (v13)
-- Description:  Enumerates all statistics objects across online user databases.
--               For each statistic, reports: auto/user created flag, leading
--               column, column count, whether it is index-backed, incremental
--               status, no-recompute flag, and (SQL 2022+) persisted sample.
--
--               has_persisted_sample is available only on SQL Server 2022
--               (v16+). A TRY/CATCH approach wraps the column reference so
--               the query degrades gracefully on earlier versions.
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
    -- has_persisted_sample column exists only on SQL Server 2022+ (v16+)
    IF @MajorVersion >= 16
    BEGIN
        SET @Sql = N'
USE ' + QUOTENAME(@DatabaseName) + N';

SELECT
    DB_NAME()                                                              AS DatabaseName,
    s.name                                                                 AS SchemaName,
    t.name                                                                 AS TableName,
    st.name                                                                AS StatisticName,
    st.stats_id                                                            AS StatsId,
    st.auto_created                                                        AS IsAutoCreated,
    st.user_created                                                        AS IsUserCreated,
    st.no_recompute                                                        AS NoRecompute,
    st.is_incremental                                                      AS IsIncremental,
    st.is_temporary                                                        AS IsTemporary,
    st.has_persisted_sample                                                AS HasPersistedSample,
    (
        SELECT TOP 1 c.name
        FROM   sys.stats_columns sc
        JOIN   sys.columns c
            ON  c.object_id = sc.object_id
            AND c.column_id = sc.column_id
        WHERE  sc.stats_id  = st.stats_id
          AND  sc.object_id = st.object_id
        ORDER BY sc.stats_column_id
    )                                                                      AS LeadingColumn,
    (
        SELECT COUNT(*)
        FROM   sys.stats_columns sc
        WHERE  sc.stats_id  = st.stats_id
          AND  sc.object_id = st.object_id
    )                                                                      AS ColumnCount,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM   sys.indexes i
            WHERE  i.object_id = st.object_id
              AND  i.name      = st.name
        ) THEN 1
        ELSE 0
    END                                                                    AS IsIndexStats
FROM sys.stats  st
JOIN sys.tables  t ON t.object_id = st.object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
ORDER BY t.name, st.name;
';
    END
    ELSE
    BEGIN
        SET @Sql = N'
USE ' + QUOTENAME(@DatabaseName) + N';

SELECT
    DB_NAME()                                                              AS DatabaseName,
    s.name                                                                 AS SchemaName,
    t.name                                                                 AS TableName,
    st.name                                                                AS StatisticName,
    st.stats_id                                                            AS StatsId,
    st.auto_created                                                        AS IsAutoCreated,
    st.user_created                                                        AS IsUserCreated,
    st.no_recompute                                                        AS NoRecompute,
    st.is_incremental                                                      AS IsIncremental,
    st.is_temporary                                                        AS IsTemporary,
    NULL                                                                   AS HasPersistedSample,
    (
        SELECT TOP 1 c.name
        FROM   sys.stats_columns sc
        JOIN   sys.columns c
            ON  c.object_id = sc.object_id
            AND c.column_id = sc.column_id
        WHERE  sc.stats_id  = st.stats_id
          AND  sc.object_id = st.object_id
        ORDER BY sc.stats_column_id
    )                                                                      AS LeadingColumn,
    (
        SELECT COUNT(*)
        FROM   sys.stats_columns sc
        WHERE  sc.stats_id  = st.stats_id
          AND  sc.object_id = st.object_id
    )                                                                      AS ColumnCount,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM   sys.indexes i
            WHERE  i.object_id = st.object_id
              AND  i.name      = st.name
        ) THEN 1
        ELSE 0
    END                                                                    AS IsIndexStats
FROM sys.stats  st
JOIN sys.tables  t ON t.object_id = st.object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
ORDER BY t.name, st.name;
';
    END

    EXEC sys.sp_executesql @Sql;

    FETCH NEXT FROM db_cursor INTO @DatabaseName;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;
