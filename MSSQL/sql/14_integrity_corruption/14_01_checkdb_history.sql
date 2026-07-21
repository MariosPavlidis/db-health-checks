-- ============================================================
-- Health Check: Ch 14 Integrity and Corruption — 14.1 CHECKDB History
-- Checklist ref: Section 14.1
-- Min SQL version: 2016 (130)
-- ============================================================
-- NOTE: CHECKDB completion messages are written to the SQL Server error log.
-- Results are retained only while the log files remain on disk.
-- Recommend a dedicated monitoring solution for long-term CHECKDB tracking.
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- Collect CHECKDB messages from the last three error log files.
-- Each log file is read separately because xp_readerrorlog does not accept
-- a log index as a variable in all contexts.

CREATE TABLE #ErrLog (
    LogDate     DATETIME,
    ProcessInfo VARCHAR(100),
    [Text]      NVARCHAR(4000)
);

INSERT INTO #ErrLog
EXEC master.dbo.xp_readerrorlog 0, 1, N'DBCC CHECKDB';

INSERT INTO #ErrLog
EXEC master.dbo.xp_readerrorlog 1, 1, N'DBCC CHECKDB';

INSERT INTO #ErrLog
EXEC master.dbo.xp_readerrorlog 2, 1, N'DBCC CHECKDB';

-- Parse the log entries: extract database name and outcome.
-- Typical completion message format:
--   DBCC CHECKDB (<dbname>) executed by <login> found 0 errors and repaired 0 errors. ...
-- Or when errors exist:
--   DBCC CHECKDB (<dbname>) ... found N errors and repaired M errors.

;WITH ParsedLog AS (
    SELECT
        el.LogDate,
        el.ProcessInfo,
        el.[Text],
        -- Extract database name from the parenthesised token after "CHECKDB"
        CASE
            WHEN el.[Text] LIKE '%DBCC CHECKDB (%'
            THEN LTRIM(RTRIM(
                    SUBSTRING(
                        el.[Text],
                        CHARINDEX('(', el.[Text]) + 1,
                        CHARINDEX(')', el.[Text]) - CHARINDEX('(', el.[Text]) - 1
                    )
                ))
            ELSE NULL
        END AS DatabaseName,
        CASE
            WHEN el.[Text] LIKE '%found 0 errors%' THEN 'CLEAN'
            WHEN el.[Text] LIKE '%errors found%'   THEN 'ERRORS_FOUND'
            WHEN el.[Text] LIKE '%CHECKDB%'        THEN 'UNKNOWN'
            ELSE 'OTHER'
        END AS CheckDbOutcome
    FROM #ErrLog el
    WHERE el.[Text] LIKE '%DBCC CHECKDB%'
),
-- Most recent CHECKDB entry per database found in the log
LatestPerDb AS (
    SELECT
        pl.DatabaseName,
        MAX(pl.LogDate)          AS LastCheckDbDate,
        COUNT(*)                 AS LogEntriesFound
    FROM ParsedLog pl
    WHERE pl.DatabaseName IS NOT NULL
    GROUP BY pl.DatabaseName
),
-- Outcome as of the latest run
LatestOutcome AS (
    SELECT
        pl.DatabaseName,
        pl.CheckDbOutcome,
        pl.[Text]                AS LastLogText,
        pl.LogDate
    FROM ParsedLog pl
    WHERE pl.DatabaseName IS NOT NULL
),
RankedOutcome AS (
    SELECT
        lo.*,
        ROW_NUMBER() OVER (PARTITION BY lo.DatabaseName ORDER BY lo.LogDate DESC) AS rn
    FROM LatestOutcome lo
)
SELECT
    d.name                                                  AS DatabaseName,
    d.state_desc                                            AS DatabaseState,
    d.recovery_model_desc                                   AS RecoveryModel,
    lpd.LastCheckDbDate,
    DATEDIFF(DAY, lpd.LastCheckDbDate, GETDATE())           AS DaysSinceLastCheckDb,
    ro.CheckDbOutcome,
    lpd.LogEntriesFound,
    ro.LastLogText,
    -- Flag databases missing from error log (no CHECKDB evidence)
    CASE WHEN lpd.DatabaseName IS NULL             THEN 'NO_CHECKDB_IN_LOG'   ELSE '' END AS MissingFlag,
    CASE WHEN ro.CheckDbOutcome = 'ERRORS_FOUND'   THEN 'ERRORS_FOUND'        ELSE '' END AS ErrorFlag,
    CASE WHEN DATEDIFF(DAY, lpd.LastCheckDbDate, GETDATE()) > 7
              OR lpd.LastCheckDbDate IS NULL        THEN 'OVERDUE'             ELSE '' END AS OverdueFlag
FROM sys.databases d
LEFT JOIN LatestPerDb  lpd ON lpd.DatabaseName = d.name
LEFT JOIN RankedOutcome ro  ON ro.DatabaseName  = d.name AND ro.rn = 1
WHERE d.database_id > 4
  AND d.state_desc = 'ONLINE'
ORDER BY DaysSinceLastCheckDb DESC, d.name;

DROP TABLE #ErrLog;
