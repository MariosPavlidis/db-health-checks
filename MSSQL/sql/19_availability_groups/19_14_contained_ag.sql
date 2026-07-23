-- ============================================================
-- Health Check: Ch 19 Availability Groups — 19.14 Contained Availability Group Config
-- Checklist ref: Section 19.14
-- Min SQL version: 2022 (160)
-- ============================================================
-- Contained AGs (SQL Server 2022+) bundle user databases, logins, and Agent jobs
-- inside the AG so they fail over as a unit.  Returns no rows on pre-2022 instances.
-- Uses dynamic SQL to avoid column-resolution errors on older versions.
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 16
BEGIN
    SELECT 'Contained availability groups require SQL Server 2022 or later' AS Note; RETURN;
END
GO

IF CAST(SERVERPROPERTY('IsHadrEnabled') AS INT) = 0
BEGIN
    SELECT 'HADR not enabled on this instance' AS Note; RETURN;
END
GO

-- Check that the column exists before referencing it (safety for pre-RTM builds)
IF NOT EXISTS (
    SELECT 1
    FROM sys.columns
    WHERE object_id = OBJECT_ID('sys.availability_groups')
      AND name = 'contained_availability_group'
)
BEGIN
    SELECT 'contained_availability_group column not found — verify SQL Server 2022 RTM or later' AS Note; RETURN;
END
GO

DECLARE @sql NVARCHAR(MAX) = N'
SELECT
    ag.name                                         AS AGName,
    ag.group_id                                     AS AGGroupId,
    ag.cluster_type_desc                            AS ClusterType,
    ag.contained_availability_group                 AS IsContainedAG,
    ag.is_distributed                               AS IsDistributed,
    ar.replica_server_name                          AS ReplicaServer,
    ar.availability_mode_desc                       AS AvailabilityMode,
    ar.failover_mode_desc                           AS FailoverMode,
    ars.role_desc                                   AS CurrentRole,
    ars.connected_state_desc                        AS ConnectedState,
    ars.synchronization_health_desc                 AS SyncHealth,
    CASE
        WHEN ag.contained_availability_group = 1
             AND ars.synchronization_health_desc <> ''HEALTHY'' THEN ''CONTAINED_AG_UNHEALTHY''
        WHEN ag.contained_availability_group = 1
             AND ars.connected_state_desc <> ''CONNECTED''      THEN ''CONTAINED_AG_DISCONNECTED''
        ELSE ''''
    END                                             AS ContainedAGFlag
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar
    ON ar.group_id = ag.group_id
JOIN sys.dm_hadr_availability_replica_states ars
    ON ars.replica_id = ar.replica_id
WHERE ag.contained_availability_group = 1
ORDER BY ag.name, ar.replica_server_name;
';

EXEC sp_executesql @sql;
