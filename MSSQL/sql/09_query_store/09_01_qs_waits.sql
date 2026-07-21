-- =============================================================================
-- 09_01_qs_waits.sql — Query Store Wait Statistics
-- Chapter 9: Query Store and Query Performance
-- Description: Iterates over all databases with Query Store enabled and
--              collects aggregated wait category statistics. Uses dynamic SQL
--              per database. sys.query_store_wait_stats requires SQL 2017+;
--              inner version guard applied inside dynamic SQL.
-- Requires:    SQL Server 2016 or later (version guard below)
-- =============================================================================

IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning];
    RETURN;
END
GO

-- Results accumulate via INSERT into a temp table so all databases are
-- returned in a single result set.
IF OBJECT_ID('tempdb..#QsWaitResults') IS NOT NULL
    DROP TABLE #QsWaitResults;

CREATE TABLE #QsWaitResults (
    DatabaseName        NVARCHAR(128),
    WaitCategory        NVARCHAR(128),
    TotalWaitTimeMs     BIGINT,
    AvgWaitTimeMs       FLOAT,
    AffectedPlanCount   INT,
    AffectedQueryCount  INT,
    CollectedAt         DATETIME
);

DECLARE @dbName     NVARCHAR(128);
DECLARE @sql        NVARCHAR(MAX);

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM sys.databases
    WHERE is_query_store_on = 1
      AND state_desc        = 'ONLINE'
      AND database_id       > 4
    ORDER BY name;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @dbName;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- sys.query_store_wait_stats requires SQL Server 2017 (version 14)+
    IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) >= 14
    BEGIN
        SET @sql = N'
USE ' + QUOTENAME(@dbName) + N';
INSERT INTO #QsWaitResults
    (DatabaseName, WaitCategory, TotalWaitTimeMs, AvgWaitTimeMs,
     AffectedPlanCount, AffectedQueryCount, CollectedAt)
SELECT
    DB_NAME()                           AS DatabaseName,
    wrs.wait_category_desc              AS WaitCategory,
    SUM(wrs.total_query_wait_time_ms)   AS TotalWaitTimeMs,
    AVG(wrs.avg_query_wait_time_ms)     AS AvgWaitTimeMs,
    COUNT(DISTINCT wrs.plan_id)         AS AffectedPlanCount,
    COUNT(DISTINCT qsq.query_id)        AS AffectedQueryCount,
    GETDATE()                           AS CollectedAt
FROM sys.query_store_wait_stats AS wrs
JOIN sys.query_store_plan  AS qsp ON qsp.plan_id  = wrs.plan_id
JOIN sys.query_store_query AS qsq ON qsq.query_id = qsp.query_id
WHERE wrs.total_query_wait_time_ms > 0
GROUP BY wrs.wait_category_desc
ORDER BY TotalWaitTimeMs DESC;
';
        BEGIN TRY
            EXEC sp_executesql @sql;
        END TRY
        BEGIN CATCH
            INSERT INTO #QsWaitResults
                (DatabaseName, WaitCategory, TotalWaitTimeMs, AvgWaitTimeMs,
                 AffectedPlanCount, AffectedQueryCount, CollectedAt)
            VALUES
                (@dbName, 'ERROR: ' + ERROR_MESSAGE(), 0, 0, 0, 0, GETDATE());
        END CATCH
    END
    ELSE
    BEGIN
        INSERT INTO #QsWaitResults
            (DatabaseName, WaitCategory, TotalWaitTimeMs, AvgWaitTimeMs,
             AffectedPlanCount, AffectedQueryCount, CollectedAt)
        VALUES
            (@dbName, 'N/A - sys.query_store_wait_stats requires SQL 2017+',
             0, 0, 0, 0, GETDATE());
    END

    FETCH NEXT FROM db_cursor INTO @dbName;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;

SELECT
    DatabaseName,
    WaitCategory,
    TotalWaitTimeMs,
    AvgWaitTimeMs,
    AffectedPlanCount,
    AffectedQueryCount,
    CollectedAt
FROM #QsWaitResults
ORDER BY DatabaseName, TotalWaitTimeMs DESC;

DROP TABLE #QsWaitResults;
