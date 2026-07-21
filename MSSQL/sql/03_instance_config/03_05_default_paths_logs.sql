-- ============================================================
-- Health Check: Ch 03 Instance Config — 3.5 Default Paths and Logs
-- Checklist ref: Section 3.5
-- Min SQL version: 2016 (130)
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- Default data, log, and backup paths
SELECT
    SERVERPROPERTY('InstanceDefaultDataPath')   AS [DefaultDataPath],
    SERVERPROPERTY('InstanceDefaultLogPath')    AS [DefaultLogPath],
    SERVERPROPERTY('InstanceDefaultBackupPath') AS [DefaultBackupPath],
    SERVERPROPERTY('ErrorLogFileName')          AS [ErrorLogPath];

GO

-- Error log file details and count retained
EXEC xp_instance_regread
    N'HKEY_LOCAL_MACHINE',
    N'SOFTWARE\Microsoft\MSSQLServer\MSSQLServer',
    N'NumErrorLogs';

GO

-- SQL Server error log: most recent entry
-- Note: sys.fn_get_audit_file is for SQL Audit binary files, not error logs.
--       Use a temp table with xp_readerrorlog instead.
CREATE TABLE #ErrorLog (LogDate DATETIME, ProcessInfo NVARCHAR(100), [Text] NVARCHAR(4000));
INSERT INTO #ErrorLog EXEC xp_readerrorlog 0, 1;
SELECT TOP 1
    LogDate     AS [LatestLogEntry],
    ProcessInfo,
    [Text]
FROM #ErrorLog
ORDER BY LogDate DESC;
DROP TABLE #ErrorLog;

GO

-- Active Extended Events sessions
SELECT
    s.name                          AS [SessionName],
    s.create_time                   AS [CreateTime],
    s.total_buffer_size             AS [BufferSizeBytes],
    s.dropped_buffer_count          AS [BufferLostPartitions],
    s.total_regular_buffers         AS [RegularBuffers],
    s.total_large_buffers           AS [LargeBuffers],
    -- Target details
    t.target_name                   AS [TargetName],
    t.execution_count               AS [TargetExecutionCount]
FROM sys.dm_xe_sessions s
JOIN sys.dm_xe_session_targets t ON t.event_session_address = s.address
ORDER BY s.name, t.target_name;

GO

-- Startup stored procedures
SELECT
    name        AS [ProcedureName],
    object_id   AS [ObjectId],
    create_date AS [CreateDate],
    modify_date AS [ModifyDate]
FROM sys.objects
WHERE type = 'P'
  AND OBJECTPROPERTY(object_id, 'ExecIsStartup') = 1;
