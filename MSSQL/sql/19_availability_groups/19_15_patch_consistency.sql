-- ============================================================
-- Health Check: Ch 19 Availability Groups — 19.15 Patch/Build Consistency
-- Checklist ref: Section 19.15
-- Min SQL version: 2016 (130)
-- ============================================================
-- T-SQL DMVs cannot directly retrieve the build version of remote AG replicas.
-- This script reports the LOCAL instance build (version, patch level, edition)
-- and lists all replica server names so the operator can:
--   1. Compare the local build against expected baseline.
--   2. Run this same script on each replica to verify consistency.
--
-- Alternatively, compare via:  SELECT @@VERSION on each replica.
-- A build mismatch between primary and secondary is supported only within
-- the Microsoft rolling-upgrade window; permanent mismatches should be resolved.
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

-- ── 1. Local instance build ───────────────────────────────────────────────────
SELECT
    CAST(SERVERPROPERTY('MachineName')      AS NVARCHAR(256)) AS MachineName,
    CAST(SERVERPROPERTY('ServerName')       AS NVARCHAR(256)) AS ServerName,
    CAST(SERVERPROPERTY('InstanceName')     AS NVARCHAR(256)) AS InstanceName,
    CAST(SERVERPROPERTY('ProductVersion')   AS NVARCHAR(20))  AS ProductVersion,
    CAST(SERVERPROPERTY('ProductLevel')     AS NVARCHAR(20))  AS ProductLevel,
    CAST(SERVERPROPERTY('ProductUpdateLevel') AS NVARCHAR(20))AS ProductUpdateLevel,
    CAST(SERVERPROPERTY('Edition')          AS NVARCHAR(128)) AS Edition,
    CAST(SERVERPROPERTY('ProductMajorVersion') AS INT)        AS MajorVersion,
    @@VERSION                                                 AS FullVersionString;

-- ── 2. AG replica server names (run this script on each to compare) ───────────
SELECT
    ag.name                                         AS AGName,
    ar.replica_server_name                          AS ReplicaServer,
    ar.endpoint_url                                 AS EndpointUrl,
    ars.role_desc                                   AS CurrentRole,
    ars.connected_state_desc                        AS ConnectedState,
    -- Instruction for the operator
    N'Run: SELECT CAST(SERVERPROPERTY(''ProductVersion'') AS NVARCHAR(20)) AS ProductVersion '
    + N'on server ' + ar.replica_server_name        AS VerifyBuildInstruction
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar
    ON ar.group_id = ag.group_id
JOIN sys.dm_hadr_availability_replica_states ars
    ON ars.replica_id = ar.replica_id
ORDER BY ag.name, ar.replica_server_name;
