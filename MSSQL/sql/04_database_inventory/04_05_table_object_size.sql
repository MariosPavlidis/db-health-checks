-- ============================================================
-- Health Check: Ch 04 Database Inventory — 4.5 Table and Object Size
-- Checklist ref: Section 4.5
-- Min SQL version: 2016 (130)
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- ── Top-50 tables by total size across all online user databases ───────────────
-- Uses a cursor over user databases (state = ONLINE, database_id > 4).
-- Dynamic SQL executes in each database context to query:
--   sys.tables, sys.indexes, sys.partitions, sys.allocation_units, sys.schemas,
--   sys.columns (for LOB detection).
-- Suspicious table names are flagged via pattern matching.

SET NOCOUNT ON;

DECLARE @dbname     SYSNAME;
DECLARE @sql        NVARCHAR(MAX);

-- Staging table for aggregated results
IF OBJECT_ID('tempdb..#TableSizes') IS NOT NULL
    DROP TABLE #TableSizes;

CREATE TABLE #TableSizes (
    DatabaseName        SYSNAME         NOT NULL,
    SchemaName          SYSNAME         NOT NULL,
    TableName           SYSNAME         NOT NULL,
    [RowCount]          BIGINT          NOT NULL,
    TotalSizeKB         BIGINT          NOT NULL,
    DataSizeKB          BIGINT          NOT NULL,
    IndexSizeKB         BIGINT          NOT NULL,
    HeapOrClustered     NVARCHAR(20)    NOT NULL,
    HasLOB              BIT             NOT NULL,
    CreateDate          DATETIME        NULL,
    ModifyDate          DATETIME        NULL,
    SuspiciousNameFlag  NVARCHAR(200)   NOT NULL
);

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM sys.databases
    WHERE state_desc = 'ONLINE'
      AND database_id > 4          -- user databases only
    ORDER BY name;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @dbname;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
    USE [' + REPLACE(@dbname, N']', N']]') + N'];

    WITH TableAlloc AS (
        SELECT
            t.object_id,
            t.name                                              AS TableName,
            s.name                                              AS SchemaName,
            t.create_date                                       AS CreateDate,
            t.modify_date                                       AS ModifyDate,
            -- Row count from the partition with index_id IN (0,1) = heap or clustered
            SUM(CASE WHEN i.index_id IN (0,1) THEN p.rows ELSE 0 END) AS [RowCount],
            -- Total size: IN_ROW_DATA + LOB_DATA + ROW_OVERFLOW_DATA for all indexes
            SUM(au.total_pages) * 8                             AS TotalSizeKB,
            -- Data size: IN_ROW_DATA pages for heap/clustered index only
            SUM(CASE
                    WHEN au.type IN (1)             -- IN_ROW_DATA
                     AND i.index_id IN (0,1)
                    THEN au.data_pages ELSE 0
                END) * 8                                        AS DataSizeKB,
            -- Index size = total - data
            (SUM(au.total_pages) - SUM(CASE
                    WHEN au.type IN (1) AND i.index_id IN (0,1)
                    THEN au.data_pages ELSE 0
                END)) * 8                                       AS IndexSizeKB,
            MAX(CASE i.index_id
                    WHEN 0 THEN ''HEAP''
                    WHEN 1 THEN ''CLUSTERED''
                    ELSE        ''NONCLUSTERED''
                END)                                            AS HeapOrClustered
        FROM sys.tables t
        JOIN sys.schemas s
            ON s.schema_id = t.schema_id
        JOIN sys.indexes i
            ON i.object_id = t.object_id
        JOIN sys.partitions p
            ON p.object_id = i.object_id
           AND p.index_id  = i.index_id
        JOIN sys.allocation_units au
            ON au.container_id = CASE
                WHEN au.type IN (1, 3) THEN p.partition_id   -- IN_ROW_DATA / ROW_OVERFLOW_DATA
                ELSE p.hobt_id                                 -- LOB_DATA uses hobt_id
               END
        GROUP BY t.object_id, t.name, s.name, t.create_date, t.modify_date
    ),
    LobTables AS (
        SELECT DISTINCT c.object_id
        FROM sys.columns c
        WHERE c.system_type_id IN (
            34,     -- image
            35,     -- text
            99,     -- ntext
            165,    -- varbinary(max)
            167,    -- varchar(max)
            231     -- nvarchar(max)
        )
        UNION
        SELECT DISTINCT c.object_id
        FROM sys.columns c
        WHERE c.system_type_id IN (240)   -- CLR UDT / xml / geography / geometry
          AND EXISTS (
              SELECT 1 FROM sys.types st
              WHERE st.user_type_id = c.user_type_id
                AND st.name IN (''xml'',''geography'',''geometry'',''hierarchyid'')
          )
    ),
    TopTables AS (
        SELECT TOP 50
            ta.*,
            CASE WHEN lt.object_id IS NOT NULL THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS HasLOB
        FROM TableAlloc ta
        LEFT JOIN LobTables lt ON lt.object_id = ta.object_id
        ORDER BY ta.TotalSizeKB DESC
    )
    SELECT
        DB_NAME()                                               AS DatabaseName,
        tt.SchemaName,
        tt.TableName,
        tt.[RowCount],
        tt.TotalSizeKB,
        tt.DataSizeKB,
        tt.IndexSizeKB,
        tt.HeapOrClustered,
        tt.HasLOB,
        tt.CreateDate,
        tt.ModifyDate,
        -- Suspicious name detection
        CASE
            WHEN tt.TableName LIKE ''%\_bak''      ESCAPE ''\'' THEN ''Suffix: _bak''
            WHEN tt.TableName LIKE ''%\_backup''   ESCAPE ''\'' THEN ''Suffix: _backup''
            WHEN tt.TableName LIKE ''%\_copy''     ESCAPE ''\'' THEN ''Suffix: _copy''
            WHEN tt.TableName LIKE ''%\_old''      ESCAPE ''\'' THEN ''Suffix: _old''
            WHEN tt.TableName LIKE ''%\_temp''     ESCAPE ''\'' THEN ''Suffix: _temp''
            WHEN tt.TableName LIKE ''%\_staging''  ESCAPE ''\'' THEN ''Suffix: _staging''
            -- Date suffix: 4+ consecutive digits at the end (e.g. Table_20240101, Table_2024)
            WHEN tt.TableName LIKE ''%[0-9][0-9][0-9][0-9]''
                THEN ''Date-suffix pattern detected''
            ELSE ''''
        END                                                     AS SuspiciousNameFlag
    FROM TopTables tt;
    ';

    BEGIN TRY
        INSERT INTO #TableSizes
        EXEC sp_executesql @sql;
    END TRY
    BEGIN CATCH
        -- Log error to a note row so the database name is visible in output
        INSERT INTO #TableSizes (
            DatabaseName, SchemaName, TableName, [RowCount],
            TotalSizeKB, DataSizeKB, IndexSizeKB,
            HeapOrClustered, HasLOB, CreateDate, ModifyDate, SuspiciousNameFlag
        )
        VALUES (
            @dbname, N'ERROR', ERROR_MESSAGE(), 0,
            0, 0, 0, N'N/A', 0, NULL, NULL, N''
        );
    END CATCH

    FETCH NEXT FROM db_cursor INTO @dbname;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;

-- Final result: sorted by database name, then total size descending
SELECT
    DatabaseName,
    SchemaName,
    TableName,
    [RowCount],
    TotalSizeKB,
    DataSizeKB,
    IndexSizeKB,
    HeapOrClustered,
    HasLOB,
    CreateDate,
    ModifyDate,
    SuspiciousNameFlag,
    CASE WHEN SuspiciousNameFlag <> '' THEN 1 ELSE 0 END AS IsSuspicious
FROM #TableSizes
ORDER BY DatabaseName, TotalSizeKB DESC;

DROP TABLE #TableSizes;
