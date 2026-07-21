-- ============================================================
-- Health Check: Ch 03 Instance Config — 3.1 Instance Identity
-- Checklist ref: Section 3.1
-- Min SQL version: 2016 (130)
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

SELECT
    SERVERPROPERTY('ServerName')              AS [ServerName],
    SERVERPROPERTY('MachineName')             AS [MachineName],
    SERVERPROPERTY('InstanceName')            AS [InstanceName],
    SERVERPROPERTY('ProductVersion')          AS [ProductVersion],
    SERVERPROPERTY('ProductMajorVersion')     AS [ProductMajorVersion],
    SERVERPROPERTY('ProductMinorVersion')     AS [ProductMinorVersion],
    SERVERPROPERTY('ProductBuild')            AS [ProductBuild],
    SERVERPROPERTY('ProductBuildType')        AS [ProductBuildType],
    SERVERPROPERTY('ProductUpdateLevel')      AS [ProductUpdateLevel],
    SERVERPROPERTY('ProductUpdateReference')  AS [ProductUpdateReference],
    SERVERPROPERTY('Edition')                 AS [Edition],
    SERVERPROPERTY('EngineEdition')           AS [EngineEdition],
    -- EngineEdition: 1=Desktop,2=Standard,3=Enterprise,4=Express,5=Azure,8=Managed
    CASE SERVERPROPERTY('EngineEdition')
        WHEN 1 THEN 'Desktop'
        WHEN 2 THEN 'Standard'
        WHEN 3 THEN 'Enterprise/Developer/Evaluation'
        WHEN 4 THEN 'Express'
        WHEN 5 THEN 'Azure SQL Database'
        WHEN 6 THEN 'Azure SQL Data Warehouse'
        WHEN 8 THEN 'Azure SQL Managed Instance'
        ELSE       'Unknown'
    END                                       AS [EngineEditionDesc],
    SERVERPROPERTY('LicenseType')             AS [LicenseType],
    SERVERPROPERTY('NumLicenses')             AS [NumLicenses],
    -- OS
    SERVERPROPERTY('OSVersion')               AS [OSVersion],
    -- Collation
    SERVERPROPERTY('Collation')               AS [ServerCollation],
    -- Clustering
    SERVERPROPERTY('IsClustered')             AS [IsClustered],
    -- HADR
    SERVERPROPERTY('IsHadrEnabled')           AS [IsHadrEnabled],
    -- XTP (In-Memory OLTP)
    SERVERPROPERTY('IsXTPSupported')          AS [IsXTPSupported],
    -- Startup
    sqlserver_start_time                      AS [SqlServerStartTime],
    DATEDIFF(HOUR, sqlserver_start_time, GETDATE()) AS [UptimeHours]
FROM sys.dm_os_sys_info;
