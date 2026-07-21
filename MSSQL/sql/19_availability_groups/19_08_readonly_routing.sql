-- ============================================================
-- Health Check: Ch 19 Availability Groups — 19.8 Read-Only Routing Configuration
-- Checklist ref: Section 19.8
-- Min SQL version: 2016 (130)
-- ============================================================
-- Reports read-only routing configuration per replica including the
-- routing list order. Flags readable secondaries that lack a routing URL,
-- which would prevent read-intent connections from being redirected.
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

IF CAST(SERVERPROPERTY('IsHadrEnabled') AS INT) = 0
BEGIN
    SELECT 'HADR not enabled' AS Note; RETURN;
END
GO

SELECT
    ag.name                                         AS AGName,
    ar.replica_server_name                          AS ReplicaServer,
    ar.secondary_role_allow_connections_desc        AS ReadableSecondary,
    ar.read_only_routing_url                        AS ReadOnlyRoutingUrl,
    -- Routing list (from sys.availability_read_only_routing_lists)
    (SELECT STRING_AGG(ar2.replica_server_name, ' -> ')
            WITHIN GROUP (ORDER BY rorl.routing_priority)
     FROM sys.availability_read_only_routing_lists rorl
     JOIN sys.availability_replicas ar2
         ON ar2.replica_id = rorl.read_only_replica_id
     WHERE rorl.replica_id   = ar.replica_id)        AS RoutingList,
    CASE WHEN ar.secondary_role_allow_connections_desc = 'ALL'
              AND (ar.read_only_routing_url IS NULL
                   OR ar.read_only_routing_url = '')
         THEN 'READABLE_NO_ROUTING_URL'
         ELSE ''
    END                                             AS RoutingFlag
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar
    ON ar.group_id = ag.group_id
ORDER BY ag.name, ar.replica_server_name;
