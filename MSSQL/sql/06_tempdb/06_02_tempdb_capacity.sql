-- ============================================================
-- Health Check: Ch 06 TempDB — 6.2 TempDB Capacity Usage
-- Checklist ref: Section 6.2
-- Min SQL version: 2016 (130)
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- ── Part 1: TempDB space usage summary ────────────────────────────────────────
SELECT
    SUM(unallocated_extent_page_count)          * 8 / 1024 AS FreeSpaceMB,
    SUM(user_object_reserved_page_count)        * 8 / 1024 AS UserObjectMB,
    SUM(internal_object_reserved_page_count)    * 8 / 1024 AS InternalObjectMB,
    SUM(version_store_reserved_page_count)      * 8 / 1024 AS VersionStoreMB,
    SUM(mixed_extent_page_count)                * 8 / 1024 AS MixedExtentMB,
    (SUM(unallocated_extent_page_count)
     + SUM(user_object_reserved_page_count)
     + SUM(internal_object_reserved_page_count)
     + SUM(version_store_reserved_page_count))  * 8 / 1024 AS TotalAllocatedMB
FROM tempdb.sys.dm_db_file_space_usage;

GO

-- ── Part 2: Top 20 sessions consuming TempDB space ────────────────────────────
SELECT TOP 20
    ssu.session_id,
    es.login_name,
    es.host_name,
    es.program_name,
    es.last_request_start_time,
    ssu.user_objects_alloc_page_count,
    ssu.user_objects_dealloc_page_count,
    -- Net user object pages held right now
    ssu.user_objects_alloc_page_count
        - ssu.user_objects_dealloc_page_count                           AS user_objects_net_pages,
    ssu.internal_objects_alloc_page_count,
    ssu.internal_objects_dealloc_page_count,
    -- Net internal object pages held right now
    ssu.internal_objects_alloc_page_count
        - ssu.internal_objects_dealloc_page_count                       AS internal_objects_net_pages,
    -- Total net TempDB pages for this session
    (ssu.user_objects_alloc_page_count     - ssu.user_objects_dealloc_page_count)
    + (ssu.internal_objects_alloc_page_count - ssu.internal_objects_dealloc_page_count)
                                                                        AS total_net_pages,
    CAST(
        ((ssu.user_objects_alloc_page_count     - ssu.user_objects_dealloc_page_count)
       + (ssu.internal_objects_alloc_page_count - ssu.internal_objects_dealloc_page_count))
        * 8.0 / 1024 AS DECIMAL(18,2))                                  AS TotalNetTempDBMB
FROM sys.dm_db_session_space_usage     ssu
JOIN sys.dm_exec_sessions              es  ON es.session_id = ssu.session_id
WHERE ssu.session_id > 50   -- exclude system sessions
  AND (ssu.user_objects_alloc_page_count     - ssu.user_objects_dealloc_page_count
     + ssu.internal_objects_alloc_page_count - ssu.internal_objects_dealloc_page_count) > 0
ORDER BY total_net_pages DESC;

GO

-- ── Part 3: Version store bloat — long-running open transactions ───────────────
-- Transactions holding the version store open cause it to grow without bound.
-- This identifies the oldest active transactions and their owning sessions.
SELECT
    at.transaction_id,
    at.name                                         AS TransactionName,
    at.transaction_begin_time,
    DATEDIFF(SECOND, at.transaction_begin_time, GETDATE())
                                                    AS AgeSeconds,
    DATEDIFF(MINUTE, at.transaction_begin_time, GETDATE())
                                                    AS AgeMinutes,
    at.transaction_type,
    CASE at.transaction_type
        WHEN 1 THEN 'Read/Write'
        WHEN 2 THEN 'Read-Only'
        WHEN 3 THEN 'System'
        WHEN 4 THEN 'Distributed'
        ELSE 'Unknown'
    END                                             AS TransactionTypeDesc,
    at.transaction_state,
    CASE at.transaction_state
        WHEN 0 THEN 'Initializing'
        WHEN 1 THEN 'Initialized, not started'
        WHEN 2 THEN 'Active'
        WHEN 3 THEN 'Ended (read-only)'
        WHEN 4 THEN 'Commit initiated (distributed)'
        WHEN 5 THEN 'Prepared, awaiting resolution'
        WHEN 6 THEN 'Committed'
        WHEN 7 THEN 'Rolling back'
        WHEN 8 THEN 'Rolled back'
        ELSE 'Unknown'
    END                                             AS TransactionStateDesc,
    -- Session details via dm_tran_session_transactions
    st.session_id,
    es.login_name,
    es.host_name,
    es.program_name,
    es.last_request_start_time
FROM sys.dm_tran_active_transactions               at
LEFT JOIN sys.dm_tran_session_transactions         st  ON st.transaction_id = at.transaction_id
LEFT JOIN sys.dm_exec_sessions                     es  ON es.session_id     = st.session_id
WHERE at.transaction_type IN (1, 4)   -- read/write and distributed
  AND at.transaction_state IN (2, 5)  -- active or prepared
ORDER BY at.transaction_begin_time ASC;
