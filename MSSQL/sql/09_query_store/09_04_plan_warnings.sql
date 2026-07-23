-- =============================================================================
-- 09_04_plan_warnings.sql — Query Store Plan Warning Detection
-- Chapter 9: Query Store and Query Performance
-- Description: Per database with Query Store enabled, identifies execution
--              plans containing warnings: implicit conversions, missing indexes,
--              TempDb spills, memory grant warnings, and key lookups.
--              Uses cursor and dynamic SQL per database.
--              Performance: plan XML is cast to NVARCHAR(MAX) once per plan
--              via CTE, not repeated per LIKE predicate. Limited to plans
--              with executions in the last 30 days. Top 200 per database.
-- Requires:    SQL Server 2016 or later (version guard below)
-- =============================================================================

IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning];
    RETURN;
END
GO

IF OBJECT_ID('tempdb..#QsPlanWarnings') IS NOT NULL
    DROP TABLE #QsPlanWarnings;

CREATE TABLE #QsPlanWarnings (
    DatabaseName          NVARCHAR(128),
    QueryId               BIGINT,
    PlanId                BIGINT,
    HasImplicitConversion BIT,
    HasMissingIndex       BIT,
    HasTempDbSpill        BIT,
    HasMemoryGrantWarning BIT,
    HasKeyLookup          BIT,
    SqlText               NVARCHAR(MAX),
    CollectedAt           DATETIME
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
    -- Cast query_plan XML to NVARCHAR(MAX) once per plan in the CTE,
    -- then apply all LIKE predicates against that single materialised string.
    -- Filter to plans executed in the last 30 days to avoid full QS scan.
    SET @sql = N'
USE ' + QUOTENAME(@dbName) + N';
;WITH PlanXml AS (
    SELECT
        qsp.query_id,
        qsp.plan_id,
        CAST(qsp.query_plan AS NVARCHAR(MAX)) AS PlanText
    FROM sys.query_store_plan AS qsp
    WHERE qsp.is_natively_compiled = 0
      AND qsp.query_plan           IS NOT NULL
      AND EXISTS (
          SELECT 1
          FROM sys.query_store_runtime_stats AS rs
          WHERE rs.plan_id             = qsp.plan_id
            AND rs.last_execution_time >= DATEADD(day, -30, GETDATE())
      )
)
INSERT INTO #QsPlanWarnings
    (DatabaseName, QueryId, PlanId, HasImplicitConversion, HasMissingIndex,
     HasTempDbSpill, HasMemoryGrantWarning, HasKeyLookup, SqlText, CollectedAt)
SELECT TOP 200
    DB_NAME()                                                               AS DatabaseName,
    px.query_id,
    px.plan_id,
    CASE WHEN px.PlanText LIKE N''%ConvertIssue%''
          OR  px.PlanText LIKE N''%PlanAffectingConvert%''
         THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END                       AS HasImplicitConversion,
    CASE WHEN px.PlanText LIKE N''%MissingIndex%''
         THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END                       AS HasMissingIndex,
    CASE WHEN px.PlanText LIKE N''%SpillToTempDb%''
         THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END                       AS HasTempDbSpill,
    CASE WHEN px.PlanText LIKE N''%MemoryGrantWarning%''
         THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END                       AS HasMemoryGrantWarning,
    CASE WHEN px.PlanText LIKE N''%Lookup=&quot;1&quot;%''
          OR  px.PlanText LIKE N''%Lookup="1"%''
         THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END                       AS HasKeyLookup,
    LEFT(qsqt.query_sql_text, 2000)                                         AS SqlText,
    GETDATE()                                                               AS CollectedAt
FROM PlanXml px
JOIN sys.query_store_query      AS qsq  ON qsq.query_id       = px.query_id
JOIN sys.query_store_query_text AS qsqt ON qsqt.query_text_id = qsq.query_text_id
WHERE px.PlanText LIKE N''%ConvertIssue%''
   OR px.PlanText LIKE N''%PlanAffectingConvert%''
   OR px.PlanText LIKE N''%MissingIndex%''
   OR px.PlanText LIKE N''%SpillToTempDb%''
   OR px.PlanText LIKE N''%MemoryGrantWarning%''
   OR px.PlanText LIKE N''%Lookup=&quot;1&quot;%''
   OR px.PlanText LIKE N''%Lookup="1"%'';
';
    BEGIN TRY
        EXEC sp_executesql @sql;
    END TRY
    BEGIN CATCH
        INSERT INTO #QsPlanWarnings (DatabaseName, SqlText, CollectedAt)
        VALUES (@dbName, 'ERROR: ' + ERROR_MESSAGE(), GETDATE());
    END CATCH

    FETCH NEXT FROM db_cursor INTO @dbName;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;

-- Summary by database and warning type
SELECT
    DatabaseName,
    COUNT(*)                                    AS TotalPlansWithWarnings,
    SUM(CAST(HasImplicitConversion AS INT))     AS ImplicitConversionCount,
    SUM(CAST(HasMissingIndex       AS INT))     AS MissingIndexCount,
    SUM(CAST(HasTempDbSpill        AS INT))     AS TempDbSpillCount,
    SUM(CAST(HasMemoryGrantWarning AS INT))     AS MemoryGrantWarningCount,
    SUM(CAST(HasKeyLookup          AS INT))     AS KeyLookupCount
FROM #QsPlanWarnings
GROUP BY DatabaseName
ORDER BY DatabaseName;

-- Detail rows
SELECT
    DatabaseName,
    QueryId,
    PlanId,
    HasImplicitConversion,
    HasMissingIndex,
    HasTempDbSpill,
    HasMemoryGrantWarning,
    HasKeyLookup,
    SqlText,
    CollectedAt
FROM #QsPlanWarnings
ORDER BY DatabaseName, QueryId, PlanId;

DROP TABLE #QsPlanWarnings;
