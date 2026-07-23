-- =============================================================================
-- Health Check: Ch 06 TempDB — 6.5 Active and Historical TempDB Spill Evidence
-- Min SQL version: SQL Server 2016
--
-- Result sets:
--   1. Active requests with task-level internal-object allocations in tempdb
--   2. Query Store historical tempdb use (SQL Server 2017+, where enabled)
-- =============================================================================
SET NOCOUNT ON;

IF TRY_CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'VERSION_GUARD' AS ResultSetName,
           'Requires SQL Server 2016 or later.' AS Note;
    RETURN;
END;

-- ── 1. Active task allocations ────────────────────────────────────────────────
;WITH TaskUsage AS
(
    SELECT
        session_id,
        request_id,
        SUM(internal_objects_alloc_page_count)           AS InternalAllocPages,
        SUM(internal_objects_dealloc_page_count)         AS InternalDeallocPages,
        SUM(user_objects_alloc_page_count)               AS UserAllocPages,
        SUM(user_objects_dealloc_page_count)             AS UserDeallocPages
    FROM tempdb.sys.dm_db_task_space_usage
    GROUP BY session_id, request_id
)
SELECT TOP (50)
    'ACTIVE_REQUEST_TEMPDB_USAGE'                        AS ResultSetName,
    tu.session_id                                       AS SessionId,
    tu.request_id                                       AS RequestId,
    es.login_name                                       AS LoginName,
    es.host_name                                        AS HostName,
    es.program_name                                     AS ProgramName,
    er.database_id                                      AS DatabaseId,
    DB_NAME(er.database_id)                             AS DatabaseName,
    er.status                                           AS RequestStatus,
    er.command                                          AS RequestCommand,
    er.start_time                                       AS RequestStartTime,
    er.cpu_time                                         AS CpuTimeMs,
    er.total_elapsed_time                               AS ElapsedTimeMs,
    er.wait_type                                        AS WaitType,
    er.wait_time                                        AS WaitTimeMs,
    er.granted_query_memory                             AS GrantedQueryMemoryPages,
    tu.InternalAllocPages                               AS InternalAllocPages,
    tu.InternalDeallocPages                             AS InternalDeallocPages,
    tu.InternalAllocPages - tu.InternalDeallocPages     AS InternalNetPages,
    CAST((tu.InternalAllocPages - tu.InternalDeallocPages) * 8.0 / 1024.0
         AS DECIMAL(18,2))                              AS InternalNetMB,
    tu.UserAllocPages - tu.UserDeallocPages             AS UserNetPages,
    CAST((tu.UserAllocPages - tu.UserDeallocPages) * 8.0 / 1024.0
         AS DECIMAL(18,2))                              AS UserNetMB,
    SUBSTRING(
        txt.text,
        (er.statement_start_offset / 2) + 1,
        ((CASE er.statement_end_offset
              WHEN -1 THEN DATALENGTH(txt.text)
              ELSE er.statement_end_offset
          END - er.statement_start_offset) / 2) + 1
    )                                                   AS CurrentStatement,
    er.query_hash                                       AS QueryHash,
    er.query_plan_hash                                  AS QueryPlanHash,
    CASE
        WHEN tu.InternalAllocPages - tu.InternalDeallocPages >= 131072
        THEN 1 ELSE 0
    END                                                 AS flag_internal_usage_over_1gb
FROM TaskUsage AS tu
JOIN sys.dm_exec_requests AS er
    ON er.session_id = tu.session_id
   AND er.request_id = tu.request_id
JOIN sys.dm_exec_sessions AS es
    ON es.session_id = tu.session_id
OUTER APPLY sys.dm_exec_sql_text(er.sql_handle) AS txt
WHERE tu.InternalAllocPages - tu.InternalDeallocPages > 0
   OR tu.UserAllocPages - tu.UserDeallocPages > 0
ORDER BY InternalNetPages DESC, UserNetPages DESC;

-- ── 2. Query Store historical tempdb use ─────────────────────────────────────
-- avg/max_tempdb_space_used are available from SQL Server 2017 (14.x).
IF TRY_CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) >= 14
BEGIN
    CREATE TABLE #QueryStoreTempdb
    (
        ResultSetName              VARCHAR(40)    NOT NULL,
        DatabaseName               SYSNAME        NOT NULL,
        QueryId                    BIGINT         NULL,
        PlanId                     BIGINT         NULL,
        ExecutionCount             BIGINT         NULL,
        WeightedAvgTempdbPages     DECIMAL(20,2)  NULL,
        MaxTempdbPages             BIGINT         NULL,
        EstimatedTotalTempdbMB     DECIMAL(20,2)  NULL,
        LastExecutionTime          DATETIMEOFFSET NULL,
        QuerySqlText               NVARCHAR(4000) NULL,
        flag_max_tempdb_over_1gb   BIT            NOT NULL
    );

    DECLARE @DatabaseName SYSNAME;
    DECLARE @Sql NVARCHAR(MAX);

    DECLARE database_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT name
        FROM sys.databases
        WHERE database_id > 4
          AND state_desc = N'ONLINE'
          AND HAS_DBACCESS(name) = 1
        ORDER BY name;

    OPEN database_cursor;
    FETCH NEXT FROM database_cursor INTO @DatabaseName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @Sql = N'
USE ' + QUOTENAME(@DatabaseName) + N';
INSERT #QueryStoreTempdb
SELECT TOP (20)
    ''QUERY_STORE_TEMPDB_USAGE'',
    DB_NAME(),
    q.query_id,
    p.plan_id,
    SUM(rs.count_executions),
    CAST(
        SUM(CONVERT(DECIMAL(38,4), rs.avg_tempdb_space_used) * rs.count_executions)
        / NULLIF(SUM(rs.count_executions), 0)
        AS DECIMAL(20,2)
    ),
    MAX(rs.max_tempdb_space_used),
    CAST(
        SUM(CONVERT(DECIMAL(38,4), rs.avg_tempdb_space_used) * rs.count_executions)
        * 8.0 / 1024.0 AS DECIMAL(20,2)
    ),
    MAX(rs.last_execution_time),
    LEFT(qt.query_sql_text, 4000),
    CASE WHEN MAX(rs.max_tempdb_space_used) >= 131072 THEN 1 ELSE 0 END
FROM sys.query_store_runtime_stats AS rs
JOIN sys.query_store_plan AS p
    ON p.plan_id = rs.plan_id
JOIN sys.query_store_query AS q
    ON q.query_id = p.query_id
JOIN sys.query_store_query_text AS qt
    ON qt.query_text_id = q.query_text_id
WHERE rs.avg_tempdb_space_used > 0
GROUP BY q.query_id, p.plan_id, qt.query_sql_text
ORDER BY EstimatedTotalTempdbMB DESC;';

        BEGIN TRY
            EXEC sys.sp_executesql @Sql;
        END TRY
        BEGIN CATCH
            -- A problem in one database must not suppress evidence from others.
            PRINT CONCAT(N'06_05 Query Store skipped for ', QUOTENAME(@DatabaseName),
                         N': ', ERROR_MESSAGE());
        END CATCH;

        FETCH NEXT FROM database_cursor INTO @DatabaseName;
    END;

    CLOSE database_cursor;
    DEALLOCATE database_cursor;

    SELECT *
    FROM #QueryStoreTempdb
    ORDER BY EstimatedTotalTempdbMB DESC, MaxTempdbPages DESC;

    DROP TABLE #QueryStoreTempdb;
END
ELSE
BEGIN
    SELECT
        'QUERY_STORE_TEMPDB_USAGE' AS ResultSetName,
        'Historical Query Store tempdb-space columns require SQL Server 2017 or later.' AS Note;
END;
