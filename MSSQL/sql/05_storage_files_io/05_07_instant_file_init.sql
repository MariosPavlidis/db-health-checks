-- ============================================================
-- Health Check: Ch 05 Storage/Files/I/O — 5.7 Instant File Initialization
-- Checklist ref: Section 5.7
-- Min SQL version: 2016 (130)
-- ============================================================
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning]; RETURN;
END
GO

-- ── Note ──────────────────────────────────────────────────────────────────────
-- Instant File Initialization (IFI) allows SQL Server to skip zeroing out
-- newly allocated data file pages, dramatically reducing the time required
-- for data file creation and autogrowth operations.
-- IFI is granted by the SE_MANAGE_VOLUME_NAME Windows privilege assigned to
-- the SQL Server service account.
-- IMPORTANT: IFI accelerates DATA FILE initialization only.
--            It does NOT affect transaction log growth, which always requires
--            zeroing to ensure the VLF space is clean before use.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Primary check via sys.dm_server_services ──────────────────────────────────
-- sys.dm_server_services was introduced in SQL Server 2012 (SP1+).
-- The instant_file_initialization_enabled column reflects whether the SQL Server
-- service account currently holds the SE_MANAGE_VOLUME_NAME privilege.
-- Requires VIEW SERVER STATE permission.

IF EXISTS (
    SELECT 1
    FROM sys.system_objects
    WHERE name = 'dm_server_services'
      AND type = 'V'  -- view
)
BEGIN
    -- Primary: match by service name pattern for the SQL Server engine service
    IF EXISTS (
        SELECT 1
        FROM sys.dm_server_services
        WHERE servicename LIKE 'SQL Server (%'
           OR servicename = 'SQL Server'
    )
    BEGIN
        SELECT
            servicename                                             AS [ServiceName],
            CASE
                WHEN instant_file_initialization_enabled = 'Y' THEN 1
                ELSE 0
            END                                                     AS [IFIEnabled],
            instant_file_initialization_enabled                     AS [IFIStatus],
            'IFI accelerates data file initialization only. It does not affect transaction log growth.'
                                                                    AS [Note]
        FROM sys.dm_server_services
        WHERE servicename LIKE 'SQL Server (%'
           OR servicename = 'SQL Server';
    END
    ELSE
    BEGIN
        -- Fallback: match by executable path for non-standard service names
        SELECT
            servicename                                             AS [ServiceName],
            CASE
                WHEN instant_file_initialization_enabled = 'Y' THEN 1
                ELSE 0
            END                                                     AS [IFIEnabled],
            instant_file_initialization_enabled                     AS [IFIStatus],
            'IFI accelerates data file initialization only. It does not affect transaction log growth.'
                                                                    AS [Note]
        FROM sys.dm_server_services
        WHERE filename LIKE '%sqlservr%';
    END;
END
ELSE
BEGIN
    SELECT
        'sys.dm_server_services is not available on this build. '
        + 'Check SE_MANAGE_VOLUME_NAME privilege for the SQL Server service account manually, '
        + 'or query the Windows Security Policy.'                   AS [Note],
        NULL                                                        AS [IFIEnabled],
        NULL                                                        AS [IFIStatus];
END;

GO
