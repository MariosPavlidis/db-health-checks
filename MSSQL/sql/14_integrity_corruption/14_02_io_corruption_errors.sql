-- ============================================================
-- Health Check: Ch 14 Integrity and Corruption — 14.2 I/O Corruption Errors
-- Checklist ref: Section 14.2
-- Min SQL version: 2016 (130)
-- ============================================================
-- Searches the SQL Server error log for hardware I/O and corruption-related
-- error messages: 823 (hard I/O), 824 (logical consistency), 825 (read-retry),
-- 832 (constant page), checksum failures, torn pages, and damaged file errors.
-- Logs 0-4 are scanned to cover recent history.
-- Note: EXEC cannot be used as a derived table source; use INSERT...EXEC directly.
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

IF OBJECT_ID('tempdb..#ErrorLogData') IS NOT NULL DROP TABLE #ErrorLogData;

CREATE TABLE #ErrorLogData (
    LogDate     DATETIME,
    ProcessInfo VARCHAR(100),
    [Text]      NVARCHAR(4000)
);

-- Error 823: Hard I/O error (OS-level)
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 0, 1, N'Error: 823';
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 1, 1, N'Error: 823';
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 2, 1, N'Error: 823';
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 3, 1, N'Error: 823';
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 4, 1, N'Error: 823';

-- Error 824: Logical consistency error
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 0, 1, N'Error: 824';
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 1, 1, N'Error: 824';
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 2, 1, N'Error: 824';
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 3, 1, N'Error: 824';
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 4, 1, N'Error: 824';

-- Error 825: Read retry succeeded (intermittent hardware problem)
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 0, 1, N'Error: 825';
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 1, 1, N'Error: 825';
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 2, 1, N'Error: 825';
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 3, 1, N'Error: 825';
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 4, 1, N'Error: 825';

-- Error 832: Constant page protection violation
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 0, 1, N'Error: 832';
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 1, 1, N'Error: 832';
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 2, 1, N'Error: 832';
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 3, 1, N'Error: 832';
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 4, 1, N'Error: 832';

-- Checksum failures
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 0, 1, N'checksum';
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 1, 1, N'checksum';
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 2, 1, N'checksum';

-- Torn page detection
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 0, 1, N'torn page';
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 1, 1, N'torn page';
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 2, 1, N'torn page';

-- Generic I/O error keyword
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 0, 1, N'I/O error';
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 1, 1, N'I/O error';
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 2, 1, N'I/O error';

-- Corruption keyword
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 0, 1, N'corrupt';
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 1, 1, N'corrupt';
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 2, 1, N'corrupt';

-- Damaged keyword
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 0, 1, N'damaged';
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 1, 1, N'damaged';
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 2, 1, N'damaged';

-- Bad page keyword
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 0, 1, N'bad page';
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 1, 1, N'bad page';
INSERT INTO #ErrorLogData EXEC master.dbo.xp_readerrorlog 2, 1, N'bad page';

-- Deduplicate (same message can match multiple search terms) and classify.
SELECT DISTINCT
    eld.LogDate,
    eld.ProcessInfo,
    eld.[Text]                                              AS ErrorText,
    CASE
        WHEN eld.[Text] LIKE '%823%'       THEN '823 - Hard I/O Error'
        WHEN eld.[Text] LIKE '%824%'       THEN '824 - Logical Consistency Error'
        WHEN eld.[Text] LIKE '%825%'       THEN '825 - Read Retry (intermittent hardware)'
        WHEN eld.[Text] LIKE '%832%'       THEN '832 - Constant Page Violation'
        WHEN eld.[Text] LIKE '%torn page%' THEN 'Torn Page Detection'
        WHEN eld.[Text] LIKE '%checksum%'  THEN 'Checksum Failure'
        WHEN eld.[Text] LIKE '%I/O error%' THEN 'I/O Error (generic)'
        WHEN eld.[Text] LIKE '%corrupt%'   THEN 'Corruption Keyword'
        WHEN eld.[Text] LIKE '%damaged%'   THEN 'Damaged Keyword'
        WHEN eld.[Text] LIKE '%bad page%'  THEN 'Bad Page Keyword'
        ELSE 'Other'
    END                                                     AS ErrorClassification,
    CASE
        WHEN eld.[Text] LIKE '%823%' OR eld.[Text] LIKE '%824%' OR eld.[Text] LIKE '%832%'
            THEN 'CRITICAL'
        WHEN eld.[Text] LIKE '%825%'
            THEN 'WARNING'
        ELSE 'INVESTIGATE'
    END                                                     AS Severity,
    DATEDIFF(DAY, eld.LogDate, GETDATE())                   AS DaysAgo
FROM #ErrorLogData eld
ORDER BY eld.LogDate DESC;

DROP TABLE #ErrorLogData;
