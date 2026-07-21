-- ============================================================
-- Health Check: Ch 04 Database Inventory — 4.1 Database Inventory
-- Checklist ref: Section 4.1
-- Min SQL version: 2016 (130)
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- ── Result set 1: Core database inventory ────────────────────────────────────
-- FILESTREAM presence is detected via sys.master_files (type = 2 = FILESTREAM).
-- In-Memory OLTP presence is detected via sys.master_files where the file is the
-- memory-optimised data container (type_desc = 'FILESTREAM' AND
-- the parent database has a MEMORY_OPTIMIZED_DATA filegroup — approximated here
-- via the known file type 'S' for checkpoint files, type = 2 with the
-- memory-optimised marker). For a reliable cross-database check the per-db
-- filegroup query lives in 04_05; here we use sys.master_files type = 2 for
-- FILESTREAM and look for at least one type = 2 file associated with the db.
-- A simpler and fully supported proxy: sys.master_files has file_type = 2 for
-- FILESTREAM containers. Memory-optimised filegroups appear as type = 2 as well
-- but the name of the file will differ. We surface both flags from sys.master_files.

SELECT
    d.database_id                                               AS [DatabaseId],
    d.name                                                      AS [DatabaseName],
    d.create_date                                               AS [CreateDate],
    d.state_desc                                                AS [StateDesc],
    d.user_access_desc                                          AS [UserAccessDesc],
    d.is_read_only                                              AS [IsReadOnly],
    SUSER_SNAME(d.owner_sid)                                    AS [OwnerName],
    d.collation_name                                            AS [CollationName],
    d.containment_desc                                          AS [ContainmentDesc],
    d.compatibility_level                                       AS [CompatibilityLevel],
    d.recovery_model_desc                                       AS [RecoveryModelDesc],
    d.log_reuse_wait_desc                                       AS [LogReuseWaitDesc],
    d.is_in_standby                                             AS [IsInStandby],
    d.is_cleanly_shutdown                                       AS [IsCleanlyShutdown],
    d.page_verify_option_desc                                   AS [PageVerifyOptionDesc],
    -- Change Data Capture
    d.is_cdc_enabled                                            AS [IsCdcEnabled],
    -- Change Tracking (LEFT JOIN to sys.change_tracking_databases)
    CASE WHEN ct.database_id IS NOT NULL THEN 1 ELSE 0 END      AS [IsChangeTrackingEnabled],
    ct.retention_period                                         AS [CTRetentionPeriod],
    ct.retention_period_units_desc                              AS [CTRetentionUnitsDesc],
    -- Service Broker
    d.service_broker_guid                                       AS [ServiceBrokerGuid],
    d.is_broker_enabled                                         AS [IsBrokerEnabled],
    -- Misc flags
    d.is_date_correlation_on                                    AS [IsDateCorrelationOn],
    d.is_fulltext_enabled                                       AS [IsFulltextEnabled],
    -- Security
    d.is_trustworthy_on                                         AS [IsTrustworthyOn],
    d.is_db_chaining_on                                         AS [IsDbChainingOn],
    -- Replication
    d.is_published                                              AS [IsPublished],
    d.is_subscribed                                             AS [IsSubscribed],
    d.is_merge_published                                        AS [IsMergePublished],
    d.is_distributor                                            AS [IsDistributor],
    -- Always On AG membership
    CASE WHEN adc.database_name IS NOT NULL THEN 1 ELSE 0 END   AS [IsInAvailabilityGroup],
    adc.group_id                                                AS [AGGroupId],
    -- FILESTREAM: at least one FILESTREAM container file (type = 2) in sys.master_files
    ISNULL(fs.HasFilestream, 0)                                 AS [HasFilestreamFilegroup],
    -- In-Memory OLTP: at least one MEMORY_OPTIMIZED_DATA file (type_desc includes 'FILESTREAM'
    -- for checkpoint file containers — detected by file_type = 2 AND physical_name ending in
    -- the well-known hk checkpoint suffix pattern, or more reliably via file_type = 2 file
    -- with data_space_id mapping to a MEMORY_OPTIMIZED_DATA filegroup via sys.filegroups.
    -- From master context sys.filegroups only shows master db; use sys.master_files type flag.
    -- We flag it as 1 when sys.master_files has a FILESTREAM-type (2) file for the db
    -- AND no explicit FILESTREAM filegroup flag above (i.e., it is an XTP checkpoint container).
    -- For a definitive check run 04_05 which uses per-db dynamic SQL.
    ISNULL(xtp.HasInMemoryOltp, 0)                             AS [HasInMemoryOltpFilegroup]
FROM sys.databases d
-- Change Tracking
LEFT JOIN sys.change_tracking_databases ct
    ON ct.database_id = d.database_id
-- Always On AG cluster membership
LEFT JOIN sys.availability_databases_cluster adc
    ON adc.database_name = d.name
-- FILESTREAM: any FILESTREAM-type file (type = 2) for this database
LEFT JOIN (
    SELECT
        mf.database_id,
        1 AS HasFilestream
    FROM sys.master_files mf
    WHERE mf.type = 2   -- FILESTREAM
    GROUP BY mf.database_id
) fs
    ON fs.database_id = d.database_id
-- In-Memory OLTP: hekaton checkpoint file container
-- type = 2 (FILESTREAM) files that belong to an XTP filegroup are distinct from
-- standard FILESTREAM containers; we detect them via the physical_name extension
-- pattern (*.hk = checkpoint files) OR we rely on 04_05 for the definitive check.
LEFT JOIN (
    SELECT
        mf.database_id,
        1 AS HasInMemoryOltp
    FROM sys.master_files mf
    WHERE mf.type = 2
      AND (   mf.physical_name LIKE '%.hk'          -- Hekaton checkpoint file
           OR mf.physical_name LIKE '%xtp%'         -- common XTP container naming
          )
    GROUP BY mf.database_id
) xtp
    ON xtp.database_id = d.database_id
ORDER BY d.name;

GO

-- ── Result set 2: Temporal history retention flag (SQL 2017+) ─────────────────
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) >= 14
BEGIN
    SELECT
        d.database_id                                   AS [DatabaseId],
        d.name                                          AS [DatabaseName],
        d.is_temporal_history_retention_enabled         AS [IsTemporalHistoryRetentionEnabled]
    FROM sys.databases d
    ORDER BY d.name;
END
