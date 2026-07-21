-- =============================================================================
-- 10_03_deadlock_history.sql — Deadlock History from Extended Events
-- Chapter 10: Blocking, Locking, and Deadlocks
-- Description: Reads deadlock graphs from the system_health Extended Events
--              session (ring buffer target and file target if configured).
--              Returns individual deadlock events, victim process info,
--              and a summary of deadlocks per day.
-- Requires:    SQL Server 2016 or later (version guard below)
-- =============================================================================

IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning];
    RETURN;
END
GO

-- ── Section A: Deadlock events from ring buffer ────────────────────────────────
;WITH DeadlockXML AS (
    SELECT
        xdr.value('@timestamp', 'datetime2')    AS DeadlockTime,
        xdr.query('.')                           AS DeadlockGraph
    FROM (
        SELECT CAST(target_data AS XML) AS TargetData
        FROM sys.dm_xe_session_targets  AS t
        JOIN sys.dm_xe_sessions          AS s
            ON s.address = t.event_session_address
        WHERE s.name        = 'system_health'
          AND t.target_name = 'ring_buffer'
    ) AS RingBuffer
    CROSS APPLY TargetData.nodes(
        '//RingBufferTarget/event[@name="xml_deadlock_report"]'
    ) AS XEventData(xdr)
)
SELECT
    d.DeadlockTime,
    d.DeadlockGraph.value(
        '(//deadlock/victim-list/victimProcess/@id)[1]',
        'NVARCHAR(50)'
    )                                                               AS VictimProcessId,
    -- Victim input buffer: locate the process node whose @id matches victim
    d.DeadlockGraph.value(
        '(//deadlock/process-list/process[1]/inputbuf)[1]',
        'NVARCHAR(MAX)'
    )                                                               AS VictimInputBuffer,
    d.DeadlockGraph.value(
        'count(//deadlock/process-list/process)',
        'INT'
    )                                                               AS ProcessCount,
    d.DeadlockGraph.value(
        '(//deadlock/resource-list/*[1]/@objectname)[1]',
        'NVARCHAR(256)'
    )                                                               AS FirstContestedObject,
    CAST(d.DeadlockGraph AS NVARCHAR(MAX))                         AS DeadlockGraphXml,
    'ring_buffer'                                                   AS Source,
    GETDATE()                                                       AS CollectedAt
FROM DeadlockXML AS d
ORDER BY d.DeadlockTime DESC;

-- ── Section B: Deadlock events from system_health file target (if present) ─────
-- Check whether a file target is active for system_health; if so, note it.
-- Actual file-target reads require sys.fn_xe_file_target_read_file which needs
-- the file path.  We surface the file path and row count here; use
-- 10_04_xe_readiness.sql to confirm the path.
SELECT
    s.name                                                          AS SessionName,
    t.target_name                                                   AS TargetName,
    CASE WHEN t.target_name = 'event_file'
         THEN CAST(t.target_data AS XML)
                  .value('(EventFileTarget/File/@name)[1]', 'NVARCHAR(500)')
         ELSE NULL END                                              AS FileTargetPath,
    t.execution_count                                               AS EventsWritten,
    t.execution_duration_ms                                         AS WriteDurationMs,
    'Use sys.fn_xe_file_target_read_file(<path>, NULL, NULL, NULL) '
        + 'filtered by event_name = ''xml_deadlock_report'' '
        + 'to read historical deadlocks beyond the ring buffer.'   AS Note,
    GETDATE()                                                       AS CollectedAt
FROM sys.dm_xe_sessions        AS s
JOIN sys.dm_xe_session_targets AS t
    ON t.event_session_address = s.address
WHERE s.name = 'system_health'
  AND t.target_name IN ('event_file', 'ring_buffer')
ORDER BY t.target_name;

-- ── Section C: Deadlock summary — count per day ────────────────────────────────
;WITH DeadlockDates AS (
    SELECT
        CAST(xdr.value('@timestamp', 'datetime2') AS DATE) AS DeadlockDate
    FROM (
        SELECT CAST(target_data AS XML) AS TargetData
        FROM sys.dm_xe_session_targets  AS t
        JOIN sys.dm_xe_sessions          AS s
            ON s.address = t.event_session_address
        WHERE s.name        = 'system_health'
          AND t.target_name = 'ring_buffer'
    ) AS RingBuffer
    CROSS APPLY TargetData.nodes(
        '//RingBufferTarget/event[@name="xml_deadlock_report"]'
    ) AS XEventData(xdr)
)
SELECT
    DeadlockDate,
    COUNT(*)                AS DeadlocksPerDay,
    GETDATE()               AS CollectedAt
FROM DeadlockDates
GROUP BY DeadlockDate

UNION ALL

-- Totals row
SELECT
    NULL                    AS DeadlockDate,
    COUNT(*)                AS DeadlocksPerDay,
    GETDATE()               AS CollectedAt
FROM (
    SELECT xdr.value('@timestamp', 'datetime2') AS DeadlockTime
    FROM (
        SELECT CAST(target_data AS XML) AS TargetData
        FROM sys.dm_xe_session_targets  AS t
        JOIN sys.dm_xe_sessions          AS s
            ON s.address = t.event_session_address
        WHERE s.name        = 'system_health'
          AND t.target_name = 'ring_buffer'
    ) AS RingBuffer
    CROSS APPLY TargetData.nodes(
        '//RingBufferTarget/event[@name="xml_deadlock_report"]'
    ) AS XEventData(xdr)
) AS AllDeadlocks

ORDER BY DeadlockDate;
