-- ============================================================
-- Health Check: Ch 04 Database Inventory — 4.3 Query Store Configuration
-- Checklist ref: Section 4.3
-- Min SQL version: 2016 (130)
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- ── Result set 1: Query Store configuration for databases where QS is enabled ──
-- sys.database_query_store_options is a per-database view; we collect it from
-- every ONLINE database via a cursor + dynamic SQL and aggregate into a single
-- result set.

DECLARE @sql       NVARCHAR(MAX);
DECLARE @dbname    SYSNAME;
DECLARE @majorVer  INT = CAST(SERVERPROPERTY('ProductMajorVersion') AS INT);

DECLARE @qs TABLE (
    DatabaseId                  INT,
    DatabaseName                SYSNAME,
    DesiredStateDesc            NVARCHAR(60),
    ActualStateDesc             NVARCHAR(60),
    ReadOnlyReason              INT,
    ReadOnlyReasonDesc          NVARCHAR(120),
    CurrentStorageSizeMB        BIGINT,
    FlushIntervalSeconds        BIGINT,
    IntervalLengthMinutes       BIGINT,
    MaxStorageSizeMB            BIGINT,
    StaleQueryThresholdDays     BIGINT,
    MaxPlansPerQuery            BIGINT,
    QueryCaptureModeDesc        NVARCHAR(60),
    SizeBasedCleanupModeDesc    NVARCHAR(60),
    -- SQL 2017+ column (wait_stats_capture_mode_desc)
    WaitStatsCaptureMode        NVARCHAR(60),
    -- Derived flags
    IsSizePressure              BIT,
    IsReadOnly                  BIT
);

DECLARE qs_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT database_id, name
    FROM sys.databases
    WHERE state_desc = 'ONLINE'
    ORDER BY name;

OPEN qs_cursor;
DECLARE @dbid INT;
FETCH NEXT FROM qs_cursor INTO @dbid, @dbname;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- Build query with optional wait_stats_capture_mode_desc column (SQL 2017+)
    SET @sql = N'
    SELECT
        DB_ID(N''' + REPLACE(@dbname, N'''', N'''''') + N''')       AS DatabaseId,
        N''' + REPLACE(@dbname, N'''', N'''''') + N'''               AS DatabaseName,
        qso.desired_state_desc,
        qso.actual_state_desc,
        qso.readonly_reason,
        CASE qso.readonly_reason
            WHEN 0  THEN ''None''
            WHEN 2  THEN ''Database in read-only mode''
            WHEN 4  THEN ''Database in single-user mode''
            WHEN 8  THEN ''Database in emergency mode''
            WHEN 65 THEN ''Storage limit reached''
            WHEN 66 THEN ''Storage limit reached (per-plan)''
            ELSE         CAST(qso.readonly_reason AS NVARCHAR(30))
        END                                                         AS ReadOnlyReasonDesc,
        qso.current_storage_size_mb,
        qso.flush_interval_seconds,
        qso.interval_length_minutes,
        qso.max_storage_size_mb,
        qso.stale_query_threshold_days,
        qso.max_plans_per_query,
        qso.query_capture_mode_desc,
        qso.size_based_cleanup_mode_desc,
        '

    -- Conditionally add wait_stats_capture_mode_desc for SQL 2017+
    IF @majorVer >= 14
        SET @sql = @sql + N'qso.wait_stats_capture_mode_desc,'
    ELSE
        SET @sql = @sql + N'CAST(NULL AS NVARCHAR(60)) AS wait_stats_capture_mode_desc,'

    SET @sql = @sql + N'
        CASE WHEN qso.current_storage_size_mb >= qso.max_storage_size_mb * 0.9 THEN 1 ELSE 0 END AS IsSizePressure,
        CASE WHEN qso.actual_state_desc = ''READ_ONLY'' THEN 1 ELSE 0 END                         AS IsReadOnly
    FROM [' + REPLACE(@dbname, N']', N']]') + N'].sys.database_query_store_options qso;';

    BEGIN TRY
        INSERT INTO @qs
        EXEC sp_executesql @sql;
    END TRY
    BEGIN CATCH
        -- Skip inaccessible databases
    END CATCH

    FETCH NEXT FROM qs_cursor INTO @dbid, @dbname;
END

CLOSE qs_cursor;
DEALLOCATE qs_cursor;

-- Emit rows only for databases that have Query Store configured (desired_state > 0)
SELECT
    DatabaseId,
    DatabaseName,
    DesiredStateDesc,
    ActualStateDesc,
    ReadOnlyReason,
    ReadOnlyReasonDesc,
    CurrentStorageSizeMB,
    FlushIntervalSeconds,
    IntervalLengthMinutes,
    MaxStorageSizeMB,
    StaleQueryThresholdDays,
    MaxPlansPerQuery,
    QueryCaptureModeDesc,
    SizeBasedCleanupModeDesc,
    WaitStatsCaptureMode,
    IsSizePressure,
    IsReadOnly
FROM @qs
WHERE DesiredStateDesc <> 'OFF'
ORDER BY DatabaseName;

GO

-- ── Result set 2: User databases missing Query Store where it would be beneficial ──
-- Targets: user databases, compat level >= 130 (SQL 2016), Query Store currently OFF.
DECLARE @sql2      NVARCHAR(MAX);
DECLARE @dbname2   SYSNAME;

DECLARE @noqs TABLE (
    DatabaseId          INT,
    DatabaseName        SYSNAME,
    CompatibilityLevel  TINYINT,
    ActualStateDesc     NVARCHAR(60),
    Recommendation      NVARCHAR(200)
);

DECLARE noqs_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT database_id, name, compatibility_level
    FROM sys.databases
    WHERE state_desc = 'ONLINE'
      AND database_id > 4           -- exclude system databases
      AND compatibility_level >= 130
    ORDER BY name;

DECLARE @dbid2 INT;
DECLARE @compat TINYINT;

OPEN noqs_cursor;
FETCH NEXT FROM noqs_cursor INTO @dbid2, @dbname2, @compat;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql2 = N'
    SELECT
        DB_ID(N''' + REPLACE(@dbname2, N'''', N'''''') + N''') AS DatabaseId,
        N''' + REPLACE(@dbname2, N'''', N'''''') + N'''         AS DatabaseName,
        ' + CAST(@compat AS NVARCHAR(5)) + N'                   AS CompatibilityLevel,
        qso.actual_state_desc                                   AS ActualStateDesc,
        N''Enable Query Store: ALTER DATABASE [' + REPLACE(@dbname2, N']', N']]') + N'] SET QUERY_STORE = ON (OPERATION_MODE = READ_WRITE);'' AS Recommendation
    FROM [' + REPLACE(@dbname2, N']', N']]') + N'].sys.database_query_store_options qso
    WHERE qso.actual_state_desc = ''OFF'';';

    BEGIN TRY
        INSERT INTO @noqs
        EXEC sp_executesql @sql2;
    END TRY
    BEGIN CATCH
        -- Skip inaccessible
    END CATCH

    FETCH NEXT FROM noqs_cursor INTO @dbid2, @dbname2, @compat;
END

CLOSE noqs_cursor;
DEALLOCATE noqs_cursor;

SELECT
    DatabaseId,
    DatabaseName,
    CompatibilityLevel,
    ActualStateDesc,
    Recommendation
FROM @noqs
ORDER BY DatabaseName;
