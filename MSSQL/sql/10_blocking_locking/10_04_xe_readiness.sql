-- =============================================================================
-- 10_04_xe_readiness.sql — Extended Events Session Readiness Check
-- Chapter 10: Blocking, Locking, and Deadlocks
-- Description: Audits the configuration and health of Extended Events sessions
--              relevant to blocking and deadlock capture: system_health,
--              AlwaysOn_health, and any session with 'deadlock' or 'blocked'
--              in the name. Reports target health, file paths, dropped events,
--              and recommendations.
-- Requires:    SQL Server 2016 or later (version guard below)
-- =============================================================================

IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning];
    RETURN;
END
GO

-- ── Section A: XE session and target overview ─────────────────────────────────
SELECT
    s.name                                                          AS SessionName,
    s.create_time                                                   AS SessionCreateTime,
    s.total_buffer_size / 1024                                      AS BufferSizeKB,
    s.dropped_event_count                                           AS DroppedEvents,
    s.dropped_buffer_count                                          AS DroppedBuffers,
    s.blocked_event_fire_time                                       AS BlockedEventFireTimeMs,
    t.target_name                                                   AS TargetName,
    t.execution_count                                               AS TargetExecCount,
    t.execution_duration_ms                                         AS TargetExecDurationMs,
    CASE WHEN t.target_name = 'event_file'
         THEN CAST(t.target_data AS XML)
                  .value('(EventFileTarget/File/@name)[1]', 'NVARCHAR(500)')
         ELSE NULL END                                              AS FileTargetPath,
    CASE WHEN t.target_name = 'ring_buffer'
         THEN CAST(t.target_data AS XML)
                  .value('(RingBufferTarget/@eventCount)[1]', 'INT')
         ELSE NULL END                                              AS RingBufferEventCount,
    CASE WHEN t.target_name = 'ring_buffer'
         THEN CAST(t.target_data AS XML)
                  .value('(RingBufferTarget/@droppedCount)[1]', 'INT')
         ELSE NULL END                                              AS RingBufferDroppedCount,
    GETDATE()                                                       AS CollectedAt
FROM sys.dm_xe_sessions        AS s
JOIN sys.dm_xe_session_targets AS t
    ON t.event_session_address = s.address
WHERE s.name IN ('system_health', 'AlwaysOn_health')
   OR s.name LIKE '%deadlock%'
   OR s.name LIKE '%blocked%'
   OR s.name LIKE '%block_process%'
ORDER BY s.name, t.target_name;

-- ── Section B: Events captured by relevant sessions ───────────────────────────
SELECT
    s.name          AS SessionName,
    e.event_name    AS EventName,
    GETDATE()       AS CollectedAt
FROM sys.dm_xe_sessions       AS s
JOIN sys.dm_xe_session_events AS e
    ON e.event_session_address = s.address
WHERE s.name IN ('system_health', 'AlwaysOn_health')
   OR s.name LIKE '%deadlock%'
   OR s.name LIKE '%blocked%'
   OR s.name LIKE '%block_process%'
ORDER BY s.name, e.event_name;

-- ── Section C: Deadlock capture health check ─────────────────────────────────
-- Verify system_health is capturing xml_deadlock_report
SELECT
    CASE WHEN EXISTS (
        SELECT 1
        FROM sys.dm_xe_sessions       AS s
        JOIN sys.dm_xe_session_events AS e
            ON e.event_session_address = s.address
        WHERE s.name = 'system_health'
          AND e.event_name = 'xml_deadlock_report'
    ) THEN 'YES' ELSE 'NO' END                                     AS SystemHealthCapturesDeadlocks,

    -- Blocked process threshold setting (must be > 0 to fire blocked_process_report)
    (SELECT CAST(value_in_use AS INT)
     FROM sys.configurations
     WHERE name = 'blocked process threshold (s)')                  AS BlockedProcessThresholdSec,

    CASE WHEN EXISTS (
        SELECT 1
        FROM sys.dm_xe_sessions       AS s
        JOIN sys.dm_xe_session_events AS e
            ON e.event_session_address = s.address
        WHERE e.event_name LIKE '%blocked_process_report%'
    ) THEN 'YES' ELSE 'NO' END                                     AS AnySessionCapturesBlockedProcess,

    CASE WHEN EXISTS (
        SELECT 1
        FROM sys.dm_xe_sessions       AS s
        JOIN sys.dm_xe_session_targets AS t
            ON t.event_session_address = s.address
        WHERE s.name = 'system_health'
          AND t.target_name = 'event_file'
    ) THEN 'YES' ELSE 'NO' END                                     AS SystemHealthHasFileTarget,

    GETDATE()                                                       AS CollectedAt;

-- ── Section D: Recommendations ────────────────────────────────────────────────
SELECT
    Recommendation,
    Detail
FROM (VALUES
    ('Verify ring buffer retention',
     'The system_health ring buffer holds only ~4 MB by default. '
     + 'If high deadlock frequency is expected, add an event_file target '
     + 'to retain deadlock history beyond the ring buffer window.'),

    ('Enable blocked process reporting',
     'Set "blocked process threshold (s)" > 0 (e.g. 5) to enable '
     + 'blocked_process_report events. Then capture them in an XE session.'),

    ('Review dropped event counts',
     'Non-zero DroppedEvents or RingBufferDroppedCount values indicate '
     + 'the ring buffer is too small. Increase max_memory for the session '
     + 'or add a file target.')
) AS Recs (Recommendation, Detail);
