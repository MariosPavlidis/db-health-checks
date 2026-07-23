-- =============================================================================
-- Chapter:      05 — Storage, Files, and I/O
-- Section:      05.08 — Per-Database Free Space Summary
-- Checklist:    5.8
-- Min Version:  SQL Server 2016 (v13)
-- Description:  Reports allocated size, used space, and free space for data
--               files and the transaction log for every online, read-write
--               database. Uses FILEPROPERTY for data file free space and
--               sys.dm_db_log_space_usage (SQL 2016+) for log metrics.
--               Rows flagged LOW_FREE_SPACE (FreePct < 10%) are candidates
--               for proactive pre-growth before autogrowth events cause
--               I/O latency spikes.
-- =============================================================================

IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning];
    RETURN;
END
GO

SET NOCOUNT ON;

IF OBJECT_ID('tempdb..#DbFreeSpace') IS NOT NULL DROP TABLE #DbFreeSpace;

CREATE TABLE #DbFreeSpace
(
    DatabaseName  SYSNAME        NOT NULL,
    DataSizeMB    DECIMAL(18,2)  NOT NULL,
    DataUsedMB    DECIMAL(18,2)  NOT NULL,
    DataFreeMB    DECIMAL(18,2)  NOT NULL,
    LogSizeMB     DECIMAL(18,2)  NOT NULL,
    LogUsedMB     DECIMAL(18,2)  NOT NULL,
    LogFreeMB     DECIMAL(18,2)  NOT NULL,
    TotalSizeMB   DECIMAL(18,2)  NOT NULL,
    TotalFreeMB   DECIMAL(18,2)  NOT NULL,
    FreePct       DECIMAL(6,2)   NOT NULL
);

DECLARE @DbName SYSNAME;
DECLARE @Sql    NVARCHAR(MAX);

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM   sys.databases
    WHERE  state_desc  = 'ONLINE'
      AND  is_read_only = 0;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @DbName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @Sql = N'
USE ' + QUOTENAME(@DbName) + N';
WITH DataFiles AS (
    SELECT
        SUM(CAST(size AS BIGINT)) * 8.0 / 1024                                       AS DataSizeMB,
        SUM(CAST(size - FILEPROPERTY(name, ''SpaceUsed'') AS BIGINT)) * 8.0 / 1024   AS DataFreeMB
    FROM sys.database_files
    WHERE type IN (0, 2)    -- data and filestream files
),
LogSpace AS (
    SELECT
        total_log_size_in_bytes / 1048576.0  AS LogSizeMB,
        used_log_space_in_bytes / 1048576.0  AS LogUsedMB
    FROM sys.dm_db_log_space_usage
)
INSERT INTO #DbFreeSpace
SELECT
    DB_NAME()                                                       AS DatabaseName,
    CAST(d.DataSizeMB                       AS DECIMAL(18,2))      AS DataSizeMB,
    CAST(d.DataSizeMB - d.DataFreeMB        AS DECIMAL(18,2))      AS DataUsedMB,
    CAST(d.DataFreeMB                       AS DECIMAL(18,2))      AS DataFreeMB,
    CAST(l.LogSizeMB                        AS DECIMAL(18,2))      AS LogSizeMB,
    CAST(l.LogUsedMB                        AS DECIMAL(18,2))      AS LogUsedMB,
    CAST(l.LogSizeMB - l.LogUsedMB         AS DECIMAL(18,2))      AS LogFreeMB,
    CAST(d.DataSizeMB + l.LogSizeMB        AS DECIMAL(18,2))      AS TotalSizeMB,
    CAST(d.DataFreeMB + (l.LogSizeMB - l.LogUsedMB) AS DECIMAL(18,2)) AS TotalFreeMB,
    CAST(
        (d.DataFreeMB + (l.LogSizeMB - l.LogUsedMB)) * 100.0
        / NULLIF(d.DataSizeMB + l.LogSizeMB, 0)
    AS DECIMAL(6,2))                                                AS FreePct
FROM DataFiles   d
CROSS JOIN LogSpace l;
';
    BEGIN TRY
        EXEC sys.sp_executesql @Sql;
    END TRY
    BEGIN CATCH
        INSERT INTO #DbFreeSpace
            (DatabaseName, DataSizeMB, DataUsedMB, DataFreeMB,
             LogSizeMB, LogUsedMB, LogFreeMB,
             TotalSizeMB, TotalFreeMB, FreePct)
        VALUES (@DbName, -1, -1, -1, -1, -1, -1, -1, -1, -1);
    END CATCH;

    FETCH NEXT FROM db_cursor INTO @DbName;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;

SELECT
    DatabaseName,
    DataSizeMB,
    DataUsedMB,
    DataFreeMB,
    LogSizeMB,
    LogUsedMB,
    LogFreeMB,
    TotalSizeMB,
    TotalFreeMB,
    FreePct,
    CASE
        WHEN FreePct < 0  THEN 'ERROR'
        WHEN FreePct < 10 THEN 'LOW_FREE_SPACE'
        WHEN FreePct < 20 THEN 'WATCH'
        ELSE                   'OK'
    END                                                             AS SpaceFlag
FROM #DbFreeSpace
ORDER BY FreePct ASC;

DROP TABLE #DbFreeSpace;
