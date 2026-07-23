-- ============================================================
-- Health Check: Ch 19 Availability Groups — 19.12 Automatic Seeding Health
-- Checklist ref: Section 19.12
-- Min SQL version: 2016 (130)
-- ============================================================
-- Query 1: Replicas configured for AUTOMATIC seeding mode.
-- Query 2: Active or recently completed automatic-seeding operations
--           from sys.dm_hadr_automatic_seeding (shows progress and state).
-- Query 3: Failed seeding entries from sys.dm_hadr_physical_seeding_stats
--           with failure code and message for diagnosis.
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

IF CAST(SERVERPROPERTY('IsHadrEnabled') AS INT) = 0
BEGIN
    SELECT 'HADR not enabled on this instance' AS Note; RETURN;
END
GO

-- ── 1. Replicas with automatic seeding mode ───────────────────────────────────
SELECT
    ag.name                                         AS AGName,
    ar.replica_server_name                          AS ReplicaServer,
    ar.seeding_mode_desc                            AS SeedingMode,
    ar.availability_mode_desc                       AS AvailabilityMode,
    ars.role_desc                                   AS CurrentRole,
    ars.connected_state_desc                        AS ConnectedState
FROM sys.availability_replicas ar
JOIN sys.availability_groups ag
    ON ag.group_id = ar.group_id
JOIN sys.dm_hadr_availability_replica_states ars
    ON ars.replica_id = ar.replica_id
WHERE ar.seeding_mode_desc = 'AUTOMATIC'
ORDER BY ag.name, ar.replica_server_name;

-- ── 2. Active/recent automatic-seeding operations ────────────────────────────
SELECT
    s.internal_state_desc                           AS SeedingState,
    d.name                                          AS DatabaseName,
    s.transfer_rate_bytes_per_second / 1024         AS TransferRateKBps,
    s.transferred_size_bytes / 1048576              AS TransferredMB,
    s.database_size_bytes / 1048576                 AS DatabaseSizeMB,
    CASE WHEN s.database_size_bytes > 0
         THEN CAST(s.transferred_size_bytes * 100.0 / s.database_size_bytes AS DECIMAL(5,1))
         ELSE 0
    END                                             AS PercentComplete,
    s.start_time_utc                                AS StartTimeUTC,
    s.end_time_utc                                  AS EndTimeUTC,
    s.estimate_time_complete_utc                    AS EstCompletionUTC
FROM sys.dm_hadr_automatic_seeding s
LEFT JOIN sys.databases d
    ON d.database_id = s.local_database_id
ORDER BY s.start_time_utc DESC;

-- ── 3. Seeding failures from physical seeding stats ──────────────────────────
SELECT
    ps.internal_state_desc                          AS SeedingState,
    d.name                                          AS DatabaseName,
    ps.failure_code                                 AS FailureCode,
    ps.failure_message                              AS FailureMessage,
    ps.failure_time_utc                             AS FailureTimeUTC,
    ps.start_time_utc                               AS StartTimeUTC,
    ps.end_time_utc                                 AS EndTimeUTC,
    ps.transfer_rate_bytes_per_second / 1024        AS TransferRateKBps,
    ps.transferred_size_bytes / 1048576             AS TransferredMB
FROM sys.dm_hadr_physical_seeding_stats ps
LEFT JOIN sys.databases d
    ON d.database_id = ps.local_database_id
WHERE ps.internal_state_desc = 'FAILED'
   OR ps.failure_code IS NOT NULL
ORDER BY COALESCE(ps.failure_time_utc, ps.start_time_utc) DESC;
