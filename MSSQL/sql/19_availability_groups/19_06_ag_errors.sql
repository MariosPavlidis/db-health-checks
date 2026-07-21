-- ============================================================
-- Health Check: Ch 19 Availability Groups — 19.6 AG Error Log Entries
-- Checklist ref: Section 19.6
-- Min SQL version: 2016 (130)
-- ============================================================
-- Searches the SQL Server error log (current and two prior archives) for
-- AG-related keywords: AlwaysOn, availability replica, endpoint, lease,
-- and seeding events. Returns distinct entries ordered by date descending.
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

IF CAST(SERVERPROPERTY('IsHadrEnabled') AS INT) = 0
BEGIN
    SELECT 'HADR not enabled' AS Note; RETURN;
END
GO

CREATE TABLE #AGErrors (LogDate DATETIME, ProcessInfo VARCHAR(100), [Text] NVARCHAR(4000));

INSERT INTO #AGErrors EXEC master.dbo.xp_readerrorlog 0, 1, N'AlwaysOn';
INSERT INTO #AGErrors EXEC master.dbo.xp_readerrorlog 1, 1, N'AlwaysOn';
INSERT INTO #AGErrors EXEC master.dbo.xp_readerrorlog 2, 1, N'AlwaysOn';
INSERT INTO #AGErrors EXEC master.dbo.xp_readerrorlog 0, 1, N'availability replica';
INSERT INTO #AGErrors EXEC master.dbo.xp_readerrorlog 0, 1, N'endpoint';
INSERT INTO #AGErrors EXEC master.dbo.xp_readerrorlog 0, 1, N'lease';
INSERT INTO #AGErrors EXEC master.dbo.xp_readerrorlog 0, 1, N'seeding';

SELECT DISTINCT
    LogDate,
    ProcessInfo,
    [Text]
FROM #AGErrors
ORDER BY LogDate DESC;

DROP TABLE #AGErrors;
