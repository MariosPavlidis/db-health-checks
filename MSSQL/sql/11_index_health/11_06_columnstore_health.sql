-- =============================================================================
-- Chapter:      11 — Index Health
-- Section:      11.06 — Columnstore Index Health
-- Checklist:    11.6
-- Min Version:  SQL Server 2016 (v13)
-- Description:  Reports row group state, deleted rows, undersized row groups,
--               and trim reasons for all columnstore indexes (clustered and
--               nonclustered) across all online user databases.
--
--               Flags:
--                 DeletedRowFlag    — > 20% deleted rows in a row group
--                                     (rebuild candidate)
--                 UndersizedFlag    — COMPRESSED row group with < 102,400 rows
--                                     (ideal is 1,048,576 per group)
--                 TrimReasonFlag    — trim reason other than NO_TRIM or
--                                     DICTIONARY_SIZE (potential load/build issue)
--
--               Also surfaces OPEN row groups, which represent the tuple mover
--               backlog. Persistent OPEN row groups indicate that the tuple
--               mover background process is lagging or stalled.
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
    DB_NAME()                                                           AS DatabaseName,
    s.name                                                              AS SchemaName,
    t.name                                                              AS TableName,
    i.name                                                              AS IndexName,
    i.type_desc                                                         AS IndexType,
    rg.row_group_id                                                     AS RowGroupId,
    rg.state_description                                                AS RowGroupState,
    rg.total_rows                                                       AS TotalRows,
    rg.deleted_rows                                                     AS DeletedRows,
    CAST(rg.size_in_bytes / 1048576.0 AS DECIMAL(18,3))                AS SizeMB,
    -- trim_reason added in SQL 2016 SP1; NULL on RTM
    NULL                                                                AS TrimReason,
    -- has_vertipaq_optimization and generation are SQL 2019+ columns
    NULL                                                                AS HasVertipaqOptimization,
    NULL                                                                AS Generation,
    -- Deleted row flag: > 20% deleted rows is a rebuild candidate
    CASE
        WHEN rg.deleted_rows * 100.0 / NULLIF(rg.total_rows, 0) > 20
            THEN ''HIGH_DELETED_ROWS''
        ELSE ''''
    END                                                                 AS DeletedRowFlag,
    -- Undersized flag: compressed row group below ideal threshold (1,048,576 rows)
    CASE
        WHEN rg.total_rows < 102400
         AND rg.state_description = ''COMPRESSED''
            THEN ''UNDERSIZED_ROWGROUP''
        ELSE ''''
    END                                                                 AS UndersizedFlag,
    -- Trim reason flag: trim_reason added in SQL 2016 SP1; always empty on RTM
    CAST('''' AS NVARCHAR(20))                                          AS TrimReasonFlag,
    -- Open row group flag: OPEN state = tuple mover backlog
    CASE
        WHEN rg.state_description = ''OPEN''
            THEN ''TUPLE_MOVER_BACKLOG''
        ELSE ''''
    END                                                                 AS OpenRowGroupFlag
FROM sys.indexes i
JOIN sys.tables  t
    ON  t.object_id = i.object_id
JOIN sys.schemas s
    ON  s.schema_id = t.schema_id
JOIN sys.column_store_row_groups rg
    ON  rg.object_id = i.object_id
    AND rg.index_id  = i.index_id
WHERE i.type IN (5, 6)   -- 5 = clustered columnstore, 6 = nonclustered columnstore
ORDER BY t.name, rg.row_group_id;
';

    EXEC sys.sp_executesql @Sql;

    FETCH NEXT FROM db_cursor INTO @DatabaseName;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;
