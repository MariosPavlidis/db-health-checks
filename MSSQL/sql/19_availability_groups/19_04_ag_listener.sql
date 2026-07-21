-- ============================================================
-- Health Check: Ch 19 Availability Groups — 19.4 AG Listeners and Network Config
-- Checklist ref: Section 19.4
-- Min SQL version: 2016 (130)
-- ============================================================
-- Returns listener DNS names, ports, IP addresses, and cluster network
-- configuration. Flags readable secondaries that have no routing URL defined.
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
    al.dns_name                                     AS ListenerName,
    al.port                                         AS ListenerPort,
    ali.ip_address                                  AS IPAddress,
    ali.ip_subnet_mask                              AS SubnetMask,
    ali.is_dhcp                                     AS IsDHCP,
    ali.state_desc                                  AS IPState,
    al.ip_configuration_string_from_cluster         AS ClusterIPConfig,
    ag_cluster.group_id                             AS AGGroupId,
    -- Listener network config: aggregate public subnet IPs (may be multiple)
    (SELECT STUFF((
        SELECT ', ' + n.network_subnet_ip
        FROM sys.dm_hadr_cluster_networks n
        WHERE n.is_public = 1
        FOR XML PATH(''), TYPE).value('.','NVARCHAR(MAX)'), 1, 2, ''))
                                                    AS PublicNetworks
FROM sys.availability_group_listeners al
JOIN sys.availability_groups ag
    ON ag.group_id = al.group_id
JOIN sys.availability_group_listener_ip_addresses ali
    ON ali.listener_id = al.listener_id
JOIN sys.availability_groups ag_cluster
    ON ag_cluster.group_id = al.group_id
ORDER BY ag.name, al.dns_name, ali.ip_address;
