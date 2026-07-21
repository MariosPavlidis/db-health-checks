-- ============================================================
-- Health Check: Ch 04 Database Inventory — 4.2 Database Options
-- Checklist ref: Section 4.2
-- Min SQL version: 2016 (130)
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- ── Result set 1: sys.databases option flags ──────────────────────────────────
SELECT
    d.database_id                               AS [DatabaseId],
    d.name                                      AS [DatabaseName],
    d.compatibility_level                       AS [CompatibilityLevel],
    -- Auto options
    d.is_auto_close_on                          AS [IsAutoCloseOn],
    d.is_auto_shrink_on                         AS [IsAutoShrinkOn],
    d.is_auto_create_stats_on                   AS [IsAutoCreateStatsOn],
    d.is_auto_update_stats_on                   AS [IsAutoUpdateStatsOn],
    d.is_auto_update_stats_async_on             AS [IsAutoUpdateStatsAsyncOn],
    -- Page verification
    d.page_verify_option_desc                   AS [PageVerifyOptionDesc],
    -- Isolation
    d.is_read_committed_snapshot_on             AS [IsReadCommittedSnapshotOn],
    d.snapshot_isolation_state_desc             AS [SnapshotIsolationStateDesc],
    -- Recovery
    d.target_recovery_time_in_seconds           AS [TargetRecoveryTimeSeconds],
    d.delayed_durability_desc                   AS [DelayedDurabilityDesc],
    -- Parameterization
    d.is_parameterization_forced                AS [IsParameterizationForced],
    -- Security
    d.is_trustworthy_on                         AS [IsTrustworthyOn],
    d.is_db_chaining_on                         AS [IsDbChainingOn],
    d.is_recursive_triggers_on                  AS [IsRecursiveTriggersOn],
    -- Broker
    d.is_broker_enabled                         AS [IsBrokerEnabled],
    -- Misc
    d.is_date_correlation_on                    AS [IsDateCorrelationOn],
    d.is_quoted_identifier_on                   AS [IsQuotedIdentifierOn],
    d.is_ansi_null_default_on                   AS [IsAnsiNullDefaultOn],
    -- Common non-default flags to flag for review
    CASE
        WHEN d.is_auto_close_on  = 1 THEN 'AUTO_CLOSE enabled'
        WHEN d.is_auto_shrink_on = 1 THEN 'AUTO_SHRINK enabled'
        WHEN d.is_trustworthy_on = 1 AND d.name NOT IN ('msdb') THEN 'TRUSTWORTHY ON (non-msdb)'
        WHEN d.is_db_chaining_on = 1 THEN 'DB chaining ON'
        ELSE ''
    END                                         AS [ReviewFlag]
FROM sys.databases d
ORDER BY d.name;

GO

-- ── Result set 2: sys.database_scoped_configurations (SQL 2016+) ─────────────
-- One row per (database, configuration_name) pairing.
-- Covers all user databases that are ONLINE.
DECLARE @sql NVARCHAR(MAX);
DECLARE @dbname SYSNAME;
DECLARE @results TABLE (
    DatabaseName    SYSNAME,
    ConfigurationId INT,
    Name            NVARCHAR(60),
    Value           SQL_VARIANT,
    ValueForSecondary SQL_VARIANT,
    IsValueDefault  BIT,
    Description     NVARCHAR(256)
);

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM sys.databases
    WHERE state_desc = 'ONLINE'
    ORDER BY name;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @dbname;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
    SELECT
        DB_NAME()           AS DatabaseName,
        dsc.configuration_id,
        dsc.name,
        dsc.value,
        dsc.value_for_secondary,
        dsc.is_value_default,
        dsc.description
    FROM [' + REPLACE(@dbname, N']', N']]') + N'].sys.database_scoped_configurations dsc
    ORDER BY dsc.name;';

    BEGIN TRY
        INSERT INTO @results
        EXEC sp_executesql @sql;
    END TRY
    BEGIN CATCH
        -- Skip databases where access is denied or unavailable
    END CATCH

    FETCH NEXT FROM db_cursor INTO @dbname;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;

SELECT
    DatabaseName,
    ConfigurationId,
    Name            AS [ConfigurationName],
    CAST(Value AS NVARCHAR(256))            AS [Value],
    CAST(ValueForSecondary AS NVARCHAR(256)) AS [ValueForSecondary],
    IsValueDefault,
    Description
FROM @results
ORDER BY DatabaseName, Name;
