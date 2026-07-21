-- =============================================================================
-- Chapter:      12 — Statistics Health
-- Section:      12.02 — Statistics Freshness
-- Checklist:    12.2
-- Min Version:  SQL Server 2016 (v13)
-- Description:  Evaluates how current statistics are across all online user
--               databases. Uses sys.dm_db_stats_properties to retrieve
--               row count, rows sampled, and modification counter without
--               executing DBCC SHOW_STATISTICS (which requires table lock).
--
--               Flags:
--                 NEVER_UPDATED    — STATS_DATE returns NULL (stats never run)
--                 STALE_HIGH_MODS  — > 30 days old AND modification counter
--                                    exceeds 1,000 rows changed
--                 HIGH_MOD_RATE    — modifications exceed 20% of table rows
--                                    (auto-update threshold for large tables)
--               Sample flags:
--                 LOW_SAMPLE       — sample rate below 10%; optimizer may
--                                    produce poor cardinality estimates
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
    DB_NAME()                                                              AS DatabaseName,
    s.name                                                                 AS SchemaName,
    t.name                                                                 AS TableName,
    st.name                                                                AS StatisticName,
    st.stats_id                                                            AS StatsId,
    STATS_DATE(st.object_id, st.stats_id)                                 AS LastUpdated,
    sp.rows                                                                AS [RowCount],
    sp.rows_sampled                                                        AS RowsSampled,
    sp.modification_counter                                                AS ModificationCounter,
    CAST(
        sp.rows_sampled * 100.0 / NULLIF(sp.rows, 0)
    AS DECIMAL(5,1))                                                       AS SamplePct,
    DATEDIFF(
        DAY,
        STATS_DATE(st.object_id, st.stats_id),
        GETDATE()
    )                                                                      AS DaysSinceUpdate,
    -- Freshness flag
    CASE
        WHEN STATS_DATE(st.object_id, st.stats_id) IS NULL
            THEN ''NEVER_UPDATED''
        WHEN DATEDIFF(DAY, STATS_DATE(st.object_id, st.stats_id), GETDATE()) > 30
             AND sp.modification_counter > 1000
            THEN ''STALE_HIGH_MODS''
        WHEN sp.modification_counter > sp.rows * 0.2
            THEN ''HIGH_MOD_RATE''
        ELSE ''OK''
    END                                                                    AS FreshnessFlag,
    -- Sample rate flag
    CASE
        WHEN sp.rows_sampled * 100.0 / NULLIF(sp.rows, 0) < 10
            THEN ''LOW_SAMPLE''
        ELSE ''OK''
    END                                                                    AS SampleFlag
FROM sys.stats st
JOIN sys.tables  t ON t.object_id = st.object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
CROSS APPLY sys.dm_db_stats_properties(st.object_id, st.stats_id) sp
WHERE t.is_ms_shipped = 0
ORDER BY sp.modification_counter DESC;
';

    EXEC sys.sp_executesql @Sql;

    FETCH NEXT FROM db_cursor INTO @DatabaseName;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;
