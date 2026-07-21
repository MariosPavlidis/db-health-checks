-- ============================================================
-- Health Check: Ch 05 Storage/Files/I/O — 5.5 File I/O Latency
-- Checklist ref: Section 5.5
-- Min SQL version: 2016 (130)
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- ── Note ──────────────────────────────────────────────────────────────────────
-- sys.dm_io_virtual_file_stats returns CUMULATIVE counters since the last
-- SQL Server service restart (or since the database was last brought online).
-- High average latencies on files with very low I/O counts (IdleFile flag)
-- should be treated with caution — a single slow initialisation read can skew
-- averages significantly on an otherwise idle file.
-- Recommended latency thresholds (Microsoft and industry guidance):
--   Data files: avg read/write latency < 20 ms  (CRITICAL > 50 ms)
--   Log files:  avg write latency < 5 ms         (CRITICAL > 10 ms)
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    d.name                                                          AS [DatabaseName],
    mf.name                                                         AS [LogicalFileName],
    mf.physical_name                                                AS [PhysicalPath],
    mf.type_desc                                                    AS [FileType],
    mf.size * 8 / 1024                                              AS [SizeMB],
    -- I/O operation counts
    vfs.num_of_reads                                                AS [Reads],
    vfs.num_of_writes                                               AS [Writes],
    -- Throughput
    vfs.num_of_bytes_read    / 1048576                              AS [BytesReadMB],
    vfs.num_of_bytes_written / 1048576                              AS [BytesWrittenMB],
    -- Stall accumulators (milliseconds)
    vfs.io_stall_read_ms                                            AS [ReadStallMs],
    vfs.io_stall_write_ms                                           AS [WriteStallMs],
    vfs.io_stall                                                    AS [TotalStallMs],
    -- Average latencies
    CASE
        WHEN vfs.num_of_reads = 0 THEN 0
        ELSE vfs.io_stall_read_ms / vfs.num_of_reads
    END                                                             AS [AvgReadLatencyMs],
    CASE
        WHEN vfs.num_of_writes = 0 THEN 0
        ELSE vfs.io_stall_write_ms / vfs.num_of_writes
    END                                                             AS [AvgWriteLatencyMs],
    CASE
        WHEN vfs.num_of_reads + vfs.num_of_writes = 0 THEN 0
        ELSE vfs.io_stall / (vfs.num_of_reads + vfs.num_of_writes)
    END                                                             AS [AvgTotalLatencyMs],
    -- ── Flag: HighReadLatency ─────────────────────────────────────────────────
    -- Data files: > 20 ms average read latency is considered elevated.
    -- Log files:  > 5 ms average read latency is considered elevated
    --             (log reads occur during recovery and log shipping; typically rare).
    CASE
        WHEN vfs.num_of_reads > 0
         AND mf.type = 0  -- data file
         AND vfs.io_stall_read_ms / vfs.num_of_reads > 20
            THEN 1
        WHEN vfs.num_of_reads > 0
         AND mf.type = 1  -- log file
         AND vfs.io_stall_read_ms / vfs.num_of_reads > 5
            THEN 1
        ELSE 0
    END                                                             AS [HighReadLatency],
    -- ── Flag: HighWriteLatency ────────────────────────────────────────────────
    -- Data files: > 20 ms average write latency is considered elevated.
    -- Log files:  > 5 ms average write latency is considered elevated
    --             (log writes are sequential and on a healthy subsystem should
    --              be sub-millisecond to low single-digit milliseconds).
    CASE
        WHEN vfs.num_of_writes > 0
         AND mf.type = 0  -- data file
         AND vfs.io_stall_write_ms / vfs.num_of_writes > 20
            THEN 1
        WHEN vfs.num_of_writes > 0
         AND mf.type = 1  -- log file
         AND vfs.io_stall_write_ms / vfs.num_of_writes > 5
            THEN 1
        ELSE 0
    END                                                             AS [HighWriteLatency],
    -- ── Flag: IdleFile ───────────────────────────────────────────────────────
    -- Files with fewer than 100 total I/O operations have statistically
    -- unreliable latency averages. A single slow operation can produce a
    -- misleadingly high average. Review these files manually.
    CASE
        WHEN vfs.num_of_reads + vfs.num_of_writes < 100 THEN 1
        ELSE 0
    END                                                             AS [IdleFile],
    -- Snapshot baseline: when counters were last reset is not directly exposed
    -- but instance start time is available from sys.dm_os_sys_info.
    (SELECT sqlserver_start_time FROM sys.dm_os_sys_info)           AS [CountersSinceInstanceStart]
FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS vfs
JOIN sys.master_files AS mf
    ON  mf.database_id = vfs.database_id
    AND mf.file_id     = vfs.file_id
JOIN sys.databases AS d
    ON  d.database_id  = vfs.database_id
ORDER BY
    -- Sort by worst total stall first to surface the highest-impact files
    TotalStallMs DESC,
    d.name,
    mf.type,
    mf.name;

GO
