-- ============================================================
-- Health Check: Ch 05 Storage/Files/I/O — 5.3 Autogrowth and Shrink Events
-- Checklist ref: Section 5.3
-- Min SQL version: 2016 (130)
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- ── Note ──────────────────────────────────────────────────────────────────────
-- This query reads from the SQL Server default trace to surface recent
-- autogrowth and shrink events. The default trace rotates and retains only
-- recent history (typically the last few rollover files, each ~20 MB).
-- Extended Events (system_health session or a custom session) is the preferred
-- mechanism for comprehensive historical capture.
-- ── Event class reference ─────────────────────────────────────────────────────
--   92 = Data File Auto Grow
--   93 = Log File Auto Grow
--   94 = Data File Auto Shrink
--   95 = Log File Auto Shrink
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Result set 1: Autogrowth and shrink events from the default trace ─────────
DECLARE @tracePath NVARCHAR(512);

SELECT TOP 1
    @tracePath = path
FROM sys.traces
WHERE is_default = 1;

IF @tracePath IS NULL
BEGIN
    SELECT 'Default trace is not enabled or path could not be determined.' AS [Note];
END
ELSE
BEGIN
    -- The default trace path points to the current file; fn_trace_gettable
    -- automatically reads all rollover files when given the base path.
    SELECT
        CAST(t.StartTime AS DATETIME2(3))                       AS [EventTime],
        t.EventClass                                             AS [EventClass],
        CASE t.EventClass
            WHEN 92 THEN 'Data File Auto Grow'
            WHEN 93 THEN 'Log File Auto Grow'
            WHEN 94 THEN 'Data File Auto Shrink'
            WHEN 95 THEN 'Log File Auto Shrink'
            ELSE          'Unknown (' + CAST(t.EventClass AS VARCHAR(5)) + ')'
        END                                                      AS [EventClassName],
        t.DatabaseName                                           AS [DatabaseName],
        t.FileName                                               AS [FileName],
        -- Duration is stored in microseconds; convert to milliseconds for readability
        t.Duration / 1000                                        AS [DurationMs],
        -- IntegerData = growth amount in 8KB pages
        t.IntegerData                                            AS [GrowthPages],
        t.IntegerData * 8 / 1024                                 AS [GrowthMB],
        CAST(t.StartTime AS DATETIME2(3))                        AS [StartTime],
        CAST(t.EndTime   AS DATETIME2(3))                        AS [EndTime]
    FROM fn_trace_gettable(@tracePath, DEFAULT) AS t
    WHERE t.EventClass IN (92, 93, 94, 95)
    ORDER BY
        t.StartTime DESC;
END;

GO

-- ── Result set 2: Repeated small autogrowth events (flag summary) ─────────────
-- Flags files that have experienced more than 5 autogrowth events where each
-- individual growth was less than 64 MB (IntegerData * 8 / 1024 < 64).
-- Repeated small autogrowths are a strong signal that initial sizing or growth
-- increments need tuning.
DECLARE @tracePath2 NVARCHAR(512);

SELECT TOP 1
    @tracePath2 = path
FROM sys.traces
WHERE is_default = 1;

IF @tracePath2 IS NULL
BEGIN
    SELECT 'Default trace is not enabled; repeated small autogrowth check skipped.' AS [Note];
END
ELSE
BEGIN
    SELECT
        t.DatabaseName                                           AS [DatabaseName],
        t.FileName                                               AS [FileName],
        CASE t.EventClass
            WHEN 92 THEN 'Data File Auto Grow'
            WHEN 93 THEN 'Log File Auto Grow'
            ELSE          'Auto Grow (class ' + CAST(t.EventClass AS VARCHAR(5)) + ')'
        END                                                      AS [EventClassName],
        COUNT(*)                                                 AS [EventCount],
        MIN(t.IntegerData * 8 / 1024)                           AS [MinGrowthMB],
        MAX(t.IntegerData * 8 / 1024)                           AS [MaxGrowthMB],
        AVG(t.IntegerData * 8 / 1024)                           AS [AvgGrowthMB],
        MIN(CAST(t.StartTime AS DATETIME2(3)))                   AS [FirstEvent],
        MAX(CAST(t.StartTime AS DATETIME2(3)))                   AS [LastEvent],
        -- Flag: repeated small autogrowths indicate file sizing problem
        CASE
            WHEN COUNT(*) > 5
             AND MAX(t.IntegerData * 8 / 1024) < 64
                THEN 1
            ELSE 0
        END                                                      AS [RepeatedSmallAutogrowthFlag]
    FROM fn_trace_gettable(@tracePath2, DEFAULT) AS t
    WHERE t.EventClass IN (92, 93)     -- growth events only; shrinks are separate
    GROUP BY
        t.DatabaseName,
        t.FileName,
        t.EventClass
    HAVING COUNT(*) > 1               -- only show files with more than one event
    ORDER BY
        EventCount DESC,
        t.DatabaseName,
        t.FileName;
END;

GO
