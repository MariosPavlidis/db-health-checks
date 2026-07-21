-- ============================================================
-- Health Check: Ch 14 Integrity and Corruption — 14.3 Suspect Pages
-- Checklist ref: Section 14.3
-- Min SQL version: 2016 (130)
-- ============================================================
-- Queries msdb.dbo.suspect_pages for all pages that have experienced
-- I/O or checksum errors.  Flags unresolved pages, recurring errors
-- (error_count > 1), and recent events within the last 30 days.
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

SELECT
    sp.database_id,
    DB_NAME(sp.database_id)                                 AS DatabaseName,
    sp.file_id                                              AS FileId,
    sp.page_id                                              AS PageId,
    sp.event_type                                           AS EventTypeCode,
    CASE sp.event_type
        WHEN 1 THEN '823 or 824 error (hard IO error or bad checksum)'
        WHEN 2 THEN 'Bad checksum'
        WHEN 3 THEN 'Torn page'
        WHEN 4 THEN 'Restored'
        WHEN 5 THEN 'Repaired (DBCC)'
        WHEN 7 THEN 'Deallocated by DBCC'
        END                                                 AS EventTypeDesc,
    sp.error_count                                          AS ErrorCount,
    sp.last_update_date                                     AS LastUpdateDate,
    CASE
        WHEN sp.event_type IN (1, 2, 3) THEN 'UNRESOLVED'
        WHEN sp.event_type IN (4, 5, 7) THEN 'RESOLVED'
        ELSE 'UNKNOWN'
    END                                                     AS ResolutionStatus,
    DATEDIFF(DAY, sp.last_update_date, GETDATE())           AS DaysSinceEvent,
    -- Flag: active corruption requiring investigation
    CASE
        WHEN sp.event_type IN (1, 2, 3)                     THEN 'UNRESOLVED_CORRUPTION'
        ELSE ''
    END                                                     AS UnresolvedFlag,
    -- Flag: page has had multiple errors — hardware instability possible
    CASE
        WHEN sp.error_count > 1                             THEN 'RECURRING_ERRORS'
        ELSE ''
    END                                                     AS RecurringFlag,
    -- Flag: event occurred within the last 30 days
    CASE
        WHEN DATEDIFF(DAY, sp.last_update_date, GETDATE()) <= 30 THEN 'RECENT_EVENT'
        ELSE ''
    END                                                     AS RecentFlag
FROM msdb.dbo.suspect_pages sp
ORDER BY sp.last_update_date DESC;
