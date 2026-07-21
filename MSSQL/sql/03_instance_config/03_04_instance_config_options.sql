-- ============================================================
-- Health Check: Ch 03 Instance Config — 3.4 Instance Configuration Options
-- Checklist ref: Section 3.4
-- Min SQL version: 2016 (130)
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- All sys.configurations values with configured vs running comparison
SELECT
    c.configuration_id                              AS [ConfigId],
    c.name                                          AS [OptionName],
    c.value                                         AS [ConfiguredValue],
    c.value_in_use                                  AS [RunningValue],
    CASE WHEN c.value <> c.value_in_use
         THEN 'PENDING RESTART' ELSE '' END         AS [RestartRequired],
    c.minimum                                       AS [MinValue],
    c.maximum                                       AS [MaxValue],
    c.is_dynamic                                    AS [IsDynamic],
    c.is_advanced                                   AS [IsAdvanced],
    c.description                                   AS [Description]
FROM sys.configurations c
ORDER BY c.name;

GO

-- Startup parameters and trace flags
-- Note: startup parameters are collected via PowerShell (registry)
-- Active trace flags
DBCC TRACESTATUS(-1) WITH NO_INFOMSGS;
