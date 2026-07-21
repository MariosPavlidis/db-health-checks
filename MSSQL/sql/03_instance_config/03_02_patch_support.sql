-- ============================================================
-- Health Check: Ch 03 Instance Config — 3.2 Patch and Support Level
-- Checklist ref: Section 3.2
-- Min SQL version: 2016 (130)
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

SELECT
    SERVERPROPERTY('ProductVersion')         AS [ProductVersion],
    SERVERPROPERTY('ProductMajorVersion')    AS [MajorVersion],
    SERVERPROPERTY('ProductBuild')           AS [BuildNumber],
    SERVERPROPERTY('ProductUpdateLevel')     AS [PatchLevel],        -- e.g. CU14
    SERVERPROPERTY('ProductUpdateReference') AS [KBReference],
    SERVERPROPERTY('ProductBuildType')       AS [BuildType],         -- OD or GDR
    -- SQL version label
    CASE CAST(SERVERPROPERTY('ProductMajorVersion') AS INT)
        WHEN 13 THEN 'SQL Server 2016'
        WHEN 14 THEN 'SQL Server 2017'
        WHEN 15 THEN 'SQL Server 2019'
        WHEN 16 THEN 'SQL Server 2022'
        ELSE       'SQL Server (version ' + CAST(SERVERPROPERTY('ProductMajorVersion') AS VARCHAR) + ')'
    END                                      AS [VersionLabel],
    -- Mainstream and extended support end dates (reference only; verify with Microsoft)
    CASE CAST(SERVERPROPERTY('ProductMajorVersion') AS INT)
        WHEN 13 THEN 'Mainstream: 2021-07-13 | Extended: 2026-07-14'
        WHEN 14 THEN 'Mainstream: 2022-10-11 | Extended: 2027-10-12'
        WHEN 15 THEN 'Mainstream: 2024-02-28 | Extended: 2029-02-28'
        WHEN 16 THEN 'Mainstream: 2028-01-11 | Extended: 2033-01-11'
        ELSE       'Verify at aka.ms/sqllifecycle'
    END                                      AS [SupportDates_Reference],
    SERVERPROPERTY('OSVersion')              AS [OSVersion],
    -- Pending reboot indicator (registry-based; available via xp_regread on some configs)
    -- Collected via PowerShell in the chapter script
    'See hc_run.log for pending reboot status' AS [PendingRebootNote];
