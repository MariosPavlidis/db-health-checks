-- ============================================================
-- Health Check: Ch 15 Security — 15.10 Server and Database Audit Coverage
-- Checklist ref: Section 15.10
-- Min SQL version: 2016 (130)
-- ============================================================
-- Query 1: Server-level audit objects — name, destination, status, retention.
-- Query 2: Server-level audit specifications per audit — which action groups
--           are being captured at the instance level.
-- Query 3: Database-level audit specifications across all online user databases —
--           which databases have audit specifications and what they capture.
-- A database with no audit specification does NOT appear in Query 3.
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- ── 1. Server-level audit objects ─────────────────────────────────────────────
SELECT
    sa.name                                         AS AuditName,
    sa.audit_id,
    sa.type_desc                                    AS DestinationType,
    sa.is_state_enabled                             AS IsEnabled,
    sa.log_file_path                                AS LogFilePath,
    sa.log_file_name                                AS LogFileName,
    sa.max_file_size                                AS MaxFileSizeMB,
    sa.max_files                                    AS MaxFiles,
    sa.max_rollover_files                           AS MaxRolloverFiles,
    sa.reserve_disk_space                           AS ReserveDiskSpace,
    sa.queue_delay                                  AS QueueDelayMs,
    sa.on_failure_desc                              AS OnFailure,
    sa.create_date                                  AS CreateDate,
    sa.modify_date                                  AS ModifyDate,
    CASE
        WHEN sa.is_state_enabled = 0 THEN 'AUDIT_DISABLED'
        WHEN sa.on_failure_desc = 'SHUTDOWN'
             AND sa.is_state_enabled = 1            THEN 'AUDIT_ON_SHUTDOWN_MODE'
        ELSE ''
    END                                             AS AuditFlag
FROM sys.server_audits sa
ORDER BY sa.is_state_enabled DESC, sa.name;

-- ── 2. Server-level audit specifications ──────────────────────────────────────
SELECT
    sa.name                                         AS AuditName,
    sas.name                                        AS SpecificationName,
    sas.is_state_enabled                            AS SpecEnabled,
    sasd.audit_action_name                          AS ActionName,
    sasd.class_desc                                 AS TargetClass,
    OBJECT_NAME(sasd.major_id)                      AS TargetObject
FROM sys.server_audit_specifications sas
JOIN sys.server_audits sa
    ON sa.audit_guid = sas.audit_guid
JOIN sys.server_audit_specification_details sasd
    ON sasd.server_specification_id = sas.server_specification_id
ORDER BY sa.name, sas.name, sasd.audit_action_name;

-- ── 3. Database-level audit specifications ────────────────────────────────────
IF OBJECT_ID('tempdb..#DBAuditSpecs') IS NOT NULL DROP TABLE #DBAuditSpecs;

CREATE TABLE #DBAuditSpecs (
    DatabaseName        NVARCHAR(128),
    AuditName           NVARCHAR(128),
    SpecificationName   NVARCHAR(128),
    SpecEnabled         BIT,
    ActionName          NVARCHAR(60),
    TargetClass         NVARCHAR(60),
    TargetSchema        NVARCHAR(128),
    TargetObject        NVARCHAR(128),
    PrincipalName       NVARCHAR(128)
);

DECLARE @db  NVARCHAR(128);
DECLARE @sql NVARCHAR(MAX);

DECLARE audit_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE state_desc = 'ONLINE' AND database_id > 4
    ORDER BY name;

OPEN audit_cur;
FETCH NEXT FROM audit_cur INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
    USE ' + QUOTENAME(@db) + N';
    INSERT INTO #DBAuditSpecs
    SELECT
        DB_NAME(),
        das.audit_name,
        das.name,
        das.is_state_enabled,
        dasd.audit_action_name,
        dasd.class_desc,
        OBJECT_SCHEMA_NAME(dasd.major_id),
        OBJECT_NAME(dasd.major_id),
        USER_NAME(dasd.audited_principal_id)
    FROM sys.database_audit_specifications das
    JOIN sys.database_audit_specification_details dasd
        ON dasd.database_specification_id = das.database_specification_id;
    ';
    BEGIN TRY EXEC sp_executesql @sql; END TRY
    BEGIN CATCH END CATCH;
    FETCH NEXT FROM audit_cur INTO @db;
END
CLOSE audit_cur; DEALLOCATE audit_cur;

SELECT * FROM #DBAuditSpecs ORDER BY DatabaseName, AuditName, ActionName;
DROP TABLE #DBAuditSpecs;
