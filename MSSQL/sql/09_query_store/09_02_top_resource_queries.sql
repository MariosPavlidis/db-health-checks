-- =============================================================================
-- 09_02_top_resource_queries.sql — Top Resource-Consuming Queries via Query Store
-- Chapter 9: Query Store and Query Performance
-- Description: Per database with Query Store enabled, identifies the top 50
--              queries by total_duration over the last 7 days. Uses cursor
--              and dynamic SQL; DatabaseName is first column in result set.
-- Requires:    SQL Server 2016 or later (version guard below)
-- =============================================================================

IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning];
    RETURN;
END
GO

IF OBJECT_ID('tempdb..#QsTopQueries') IS NOT NULL
    DROP TABLE #QsTopQueries;

CREATE TABLE #QsTopQueries (
    DatabaseName            NVARCHAR(128),
    QueryId                 BIGINT,
    QueryHash               BINARY(8),
    PlanId                  BIGINT,
    QueryPlanHash           BINARY(8),
    SqlText                 NVARCHAR(MAX),
    ExecutionCount          BIGINT,
    AvgDurationMs           FLOAT,
    MinDurationMs           FLOAT,
    MaxDurationMs           FLOAT,
    TotalDurationMs         FLOAT,
    AvgCpuMs                FLOAT,
    TotalCpuMs              FLOAT,
    AvgLogicalReads         FLOAT,
    TotalLogicalReads       FLOAT,
    AvgPhysicalReads        FLOAT,
    AvgLogicalWrites        FLOAT,
    AvgRows                 FLOAT,
    AvgMemGrantMB           FLOAT,
    AvgTempDbMB             FLOAT,
    CollectedAt             DATETIME
);

DECLARE @dbName NVARCHAR(128);
DECLARE @sql    NVARCHAR(MAX);

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
    SET @sql = N'
USE ' + QUOTENAME(@dbName) + N';
INSERT INTO #QsTopQueries
    (DatabaseName, QueryId, QueryHash, PlanId, QueryPlanHash, SqlText,
     ExecutionCount, AvgDurationMs, MinDurationMs, MaxDurationMs, TotalDurationMs,
     AvgCpuMs, TotalCpuMs, AvgLogicalReads, TotalLogicalReads, AvgPhysicalReads,
     AvgLogicalWrites, AvgRows, AvgMemGrantMB, AvgTempDbMB, CollectedAt)
SELECT TOP 50
    DB_NAME()                                       AS DatabaseName,
    qsq.query_id,
    qsq.query_hash,
    qsp.plan_id,
    qsp.query_plan_hash,
    qsqt.query_sql_text                             AS SqlText,
    rs.count_executions                             AS ExecutionCount,
    rs.avg_duration        / 1000.0                 AS AvgDurationMs,
    rs.min_duration        / 1000.0                 AS MinDurationMs,
    rs.max_duration        / 1000.0                 AS MaxDurationMs,
    rs.avg_duration * rs.count_executions / 1000.0  AS TotalDurationMs,
    rs.avg_cpu_time        / 1000.0                 AS AvgCpuMs,
    rs.avg_cpu_time * rs.count_executions / 1000.0  AS TotalCpuMs,
    rs.avg_logical_io_reads                         AS AvgLogicalReads,
    rs.avg_logical_io_reads * rs.count_executions   AS TotalLogicalReads,
    rs.avg_physical_io_reads                        AS AvgPhysicalReads,
    rs.avg_logical_io_writes                        AS AvgLogicalWrites,
    rs.avg_rowcount                                 AS AvgRows,
    rs.avg_query_max_used_memory * 8 / 1024.0       AS AvgMemGrantMB,
    rs.avg_tempdb_space_used     * 8 / 1024.0       AS AvgTempDbMB,
    GETDATE()                                       AS CollectedAt
FROM sys.query_store_query      AS qsq
JOIN sys.query_store_query_text AS qsqt ON qsqt.query_text_id = qsq.query_text_id
JOIN sys.query_store_plan       AS qsp  ON qsp.query_id        = qsq.query_id
JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id         = qsp.plan_id
WHERE rs.last_execution_time >= DATEADD(DAY, -7, GETUTCDATE())
ORDER BY rs.avg_duration * rs.count_executions DESC;
';
    BEGIN TRY
        EXEC sp_executesql @sql;
    END TRY
    BEGIN CATCH
        -- Log error row so the database is still represented in results
        INSERT INTO #QsTopQueries (DatabaseName, SqlText, CollectedAt)
        VALUES (@dbName, 'ERROR: ' + ERROR_MESSAGE(), GETDATE());
    END CATCH

    FETCH NEXT FROM db_cursor INTO @dbName;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;

SELECT
    DatabaseName,
    QueryId,
    QueryHash,
    PlanId,
    QueryPlanHash,
    SqlText,
    ExecutionCount,
    AvgDurationMs,
    MinDurationMs,
    MaxDurationMs,
    TotalDurationMs,
    AvgCpuMs,
    TotalCpuMs,
    AvgLogicalReads,
    TotalLogicalReads,
    AvgPhysicalReads,
    AvgLogicalWrites,
    AvgRows,
    AvgMemGrantMB,
    AvgTempDbMB,
    CollectedAt
FROM #QsTopQueries
ORDER BY DatabaseName, TotalDurationMs DESC;

DROP TABLE #QsTopQueries;
