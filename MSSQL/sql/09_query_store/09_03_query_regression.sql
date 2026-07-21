-- =============================================================================
-- 09_03_query_regression.sql — Query Store Regression and Plan Forcing Analysis
-- Chapter 9: Query Store and Query Performance
-- Description: Per database with Query Store enabled, identifies queries with
--              multiple plans (plan regression candidates), forced plans,
--              plan forcing failures, and recent duration regressions.
--              Uses cursor and dynamic SQL per database.
-- Requires:    SQL Server 2016 or later (version guard below)
-- =============================================================================

IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning];
    RETURN;
END
GO

-- ── Temp tables for each result category ─────────────────────────────────────
IF OBJECT_ID('tempdb..#QsMultiPlan')      IS NOT NULL DROP TABLE #QsMultiPlan;
IF OBJECT_ID('tempdb..#QsForcedPlans')    IS NOT NULL DROP TABLE #QsForcedPlans;
IF OBJECT_ID('tempdb..#QsForceFailed')    IS NOT NULL DROP TABLE #QsForceFailed;
IF OBJECT_ID('tempdb..#QsRegressions')    IS NOT NULL DROP TABLE #QsRegressions;

CREATE TABLE #QsMultiPlan (
    DatabaseName        NVARCHAR(128),
    QueryId             BIGINT,
    PlanCount           INT,
    BestAvgDurationMs   FLOAT,
    WorstAvgDurationMs  FLOAT,
    DurationVarianceRatio FLOAT,
    CollectedAt         DATETIME
);

CREATE TABLE #QsForcedPlans (
    DatabaseName        NVARCHAR(128),
    QueryId             BIGINT,
    PlanId              BIGINT,
    QueryPlanHash       BINARY(8),
    IsForcedPlan        BIT,
    ForceFailureCount   INT,
    LastForceFailureReason NVARCHAR(4000),
    ForcedPlanModified  DATETIME,
    CollectedAt         DATETIME
);

CREATE TABLE #QsForceFailed (
    DatabaseName            NVARCHAR(128),
    QueryId                 BIGINT,
    PlanId                  BIGINT,
    ForceFailureCount       INT,
    LastForceFailureReason  NVARCHAR(4000),
    CollectedAt             DATETIME
);

CREATE TABLE #QsRegressions (
    DatabaseName            NVARCHAR(128),
    QueryId                 BIGINT,
    PlanId                  BIGINT,
    RecentAvgDurationMs     FLOAT,
    PreviousAvgDurationMs   FLOAT,
    RegressionRatio         FLOAT,
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

    -- 1. Queries with multiple plans
    SET @sql = N'
USE ' + QUOTENAME(@dbName) + N';
INSERT INTO #QsMultiPlan
    (DatabaseName, QueryId, PlanCount, BestAvgDurationMs, WorstAvgDurationMs,
     DurationVarianceRatio, CollectedAt)
SELECT
    DB_NAME()                                                               AS DatabaseName,
    qsp.query_id,
    COUNT(DISTINCT qsp.plan_id)                                             AS PlanCount,
    MIN(rs.avg_duration) / 1000.0                                           AS BestAvgDurationMs,
    MAX(rs.avg_duration) / 1000.0                                           AS WorstAvgDurationMs,
    MAX(rs.avg_duration) / NULLIF(MIN(rs.avg_duration), 0)                  AS DurationVarianceRatio,
    GETDATE()                                                               AS CollectedAt
FROM sys.query_store_plan          AS qsp
JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = qsp.plan_id
GROUP BY qsp.query_id
HAVING COUNT(DISTINCT qsp.plan_id) > 1
ORDER BY DurationVarianceRatio DESC;
';
    BEGIN TRY
        EXEC sp_executesql @sql;
    END TRY
    BEGIN CATCH
        INSERT INTO #QsMultiPlan (DatabaseName, CollectedAt)
        VALUES (@dbName + ' ERROR: ' + ERROR_MESSAGE(), GETDATE());
    END CATCH

    -- 2. Forced plans and their status
    SET @sql = N'
USE ' + QUOTENAME(@dbName) + N';
INSERT INTO #QsForcedPlans
    (DatabaseName, QueryId, PlanId, QueryPlanHash, IsForcedPlan,
     ForceFailureCount, LastForceFailureReason, ForcedPlanModified, CollectedAt)
SELECT
    DB_NAME()                       AS DatabaseName,
    qsp.query_id,
    qsp.plan_id,
    qsp.query_plan_hash,
    qsp.is_forced_plan,
    qsp.force_failure_count,
    qsp.last_force_failure_reason_desc,
    qsp.last_compile_start_time     AS ForcedPlanModified,
    GETDATE()                       AS CollectedAt
FROM sys.query_store_plan AS qsp
WHERE qsp.is_forced_plan = 1
ORDER BY qsp.force_failure_count DESC;
';
    BEGIN TRY
        EXEC sp_executesql @sql;
    END TRY
    BEGIN CATCH
        INSERT INTO #QsForcedPlans (DatabaseName, CollectedAt)
        VALUES (@dbName + ' ERROR: ' + ERROR_MESSAGE(), GETDATE());
    END CATCH

    -- 3. Plan forcing failures
    SET @sql = N'
USE ' + QUOTENAME(@dbName) + N';
INSERT INTO #QsForceFailed
    (DatabaseName, QueryId, PlanId, ForceFailureCount,
     LastForceFailureReason, CollectedAt)
SELECT
    DB_NAME()                           AS DatabaseName,
    qsp.query_id,
    qsp.plan_id,
    qsp.force_failure_count,
    qsp.last_force_failure_reason_desc  AS LastForceFailureReason,
    GETDATE()                           AS CollectedAt
FROM sys.query_store_plan AS qsp
WHERE qsp.is_forced_plan    = 1
  AND qsp.force_failure_count > 0
ORDER BY qsp.force_failure_count DESC;
';
    BEGIN TRY
        EXEC sp_executesql @sql;
    END TRY
    BEGIN CATCH
        INSERT INTO #QsForceFailed (DatabaseName, CollectedAt)
        VALUES (@dbName + ' ERROR: ' + ERROR_MESSAGE(), GETDATE());
    END CATCH

    -- 4. Recent regressions: last interval avg_duration > previous * 2
    SET @sql = N'
USE ' + QUOTENAME(@dbName) + N';
INSERT INTO #QsRegressions
    (DatabaseName, QueryId, PlanId, RecentAvgDurationMs,
     PreviousAvgDurationMs, RegressionRatio, CollectedAt)
SELECT
    DB_NAME()                                   AS DatabaseName,
    recent.query_id,
    recent.plan_id,
    recent.avg_duration / 1000.0                AS RecentAvgDurationMs,
    prev.avg_duration   / 1000.0                AS PreviousAvgDurationMs,
    recent.avg_duration / NULLIF(prev.avg_duration, 0) AS RegressionRatio,
    GETDATE()                                   AS CollectedAt
FROM (
    SELECT
        qsp.query_id,
        rs.plan_id,
        rs.avg_duration,
        ROW_NUMBER() OVER (PARTITION BY qsp.query_id ORDER BY rs.last_execution_time DESC) AS rn
    FROM sys.query_store_runtime_stats AS rs
    JOIN sys.query_store_plan          AS qsp ON qsp.plan_id = rs.plan_id
) AS recent
JOIN (
    SELECT
        qsp.query_id,
        rs.plan_id,
        rs.avg_duration,
        ROW_NUMBER() OVER (PARTITION BY qsp.query_id ORDER BY rs.last_execution_time DESC) AS rn
    FROM sys.query_store_runtime_stats AS rs
    JOIN sys.query_store_plan          AS qsp ON qsp.plan_id = rs.plan_id
) AS prev
    ON  prev.query_id = recent.query_id
    AND prev.rn       = 2
WHERE recent.rn = 1
  AND recent.avg_duration > prev.avg_duration * 2
  AND prev.avg_duration   > 0
ORDER BY RegressionRatio DESC;
';
    BEGIN TRY
        EXEC sp_executesql @sql;
    END TRY
    BEGIN CATCH
        INSERT INTO #QsRegressions (DatabaseName, CollectedAt)
        VALUES (@dbName + ' ERROR: ' + ERROR_MESSAGE(), GETDATE());
    END CATCH

    FETCH NEXT FROM db_cursor INTO @dbName;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;

-- Return all four result sets
SELECT DatabaseName, QueryId, PlanCount, BestAvgDurationMs,
       WorstAvgDurationMs, DurationVarianceRatio, CollectedAt
FROM #QsMultiPlan
ORDER BY DatabaseName, DurationVarianceRatio DESC;

SELECT DatabaseName, QueryId, PlanId, QueryPlanHash, IsForcedPlan,
       ForceFailureCount, LastForceFailureReason, ForcedPlanModified, CollectedAt
FROM #QsForcedPlans
ORDER BY DatabaseName, ForceFailureCount DESC;

SELECT DatabaseName, QueryId, PlanId, ForceFailureCount,
       LastForceFailureReason, CollectedAt
FROM #QsForceFailed
ORDER BY DatabaseName, ForceFailureCount DESC;

SELECT DatabaseName, QueryId, PlanId, RecentAvgDurationMs,
       PreviousAvgDurationMs, RegressionRatio, CollectedAt
FROM #QsRegressions
ORDER BY DatabaseName, RegressionRatio DESC;

DROP TABLE #QsMultiPlan;
DROP TABLE #QsForcedPlans;
DROP TABLE #QsForceFailed;
DROP TABLE #QsRegressions;
