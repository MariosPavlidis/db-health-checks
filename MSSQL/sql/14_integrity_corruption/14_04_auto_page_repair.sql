-- ============================================================
-- Health Check: Ch 14 Integrity and Corruption — 14.4 Auto Page Repair (HADR)
-- Checklist ref: Section 14.4
-- Min SQL version: 2016 (130)
-- ============================================================
-- Queries sys.dm_hadr_auto_page_repair to identify pages that were
-- automatically repaired (or attempted) via Always On AG mirroring.
-- Repeated repair attempts on the same page indicate underlying hardware issues.
-- Only runs when HADR is enabled on the instance.
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

IF CAST(SERVERPROPERTY('IsHadrEnabled') AS INT) = 1
BEGIN
    SELECT
        ag.name                                                     AS AGName,
        DB_NAME(apr.database_id)                                    AS DatabaseName,
        apr.file_id                                                 AS FileId,
        apr.page_id                                                 AS PageId,
        apr.error_type                                              AS ErrorType,
        apr.page_status                                             AS PageStatus,
        CASE apr.page_status
            WHEN 2 THEN 'Queued for repair'
            WHEN 3 THEN 'Repair in progress'
            WHEN 4 THEN 'Repair succeeded'
            WHEN 5 THEN 'Repair failed'
            WHEN 6 THEN 'Not repairable'
            END                                                     AS PageStatusDesc,
        apr.modification_time                                       AS ModificationTime,
        DATEDIFF(DAY, apr.modification_time, GETDATE())             AS DaysAgo,
        -- Count repair attempts for the same page across this DMV's retained history
        COUNT(*) OVER (
            PARTITION BY apr.database_id, apr.file_id, apr.page_id
        )                                                           AS RepairAttemptCount,
        -- Flag pages that failed or cannot be repaired
        CASE
            WHEN apr.page_status IN (5, 6)  THEN 'REPAIR_FAILED'
            ELSE ''
        END                                                         AS RepairFailureFlag,
        -- Flag pages with more than one repair attempt (recurring issue)
        CASE
            WHEN COUNT(*) OVER (
                PARTITION BY apr.database_id, apr.file_id, apr.page_id
            ) > 1                           THEN 'RECURRING_REPAIR'
            ELSE ''
        END                                                         AS RecurringRepairFlag
    FROM sys.dm_hadr_auto_page_repair apr
    JOIN sys.databases d
        ON d.database_id = apr.database_id
    JOIN sys.availability_databases_cluster adc
        ON adc.database_name = d.name
    JOIN sys.availability_groups ag
        ON ag.group_id = adc.group_id
    ORDER BY apr.modification_time DESC;
END
ELSE
BEGIN
    SELECT 'HADR not enabled on this instance - auto page repair not applicable' AS Note;
END
