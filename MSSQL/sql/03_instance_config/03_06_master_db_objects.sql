-- =============================================================================
-- Chapter:      03 — Instance Configuration
-- Section:      03.06 — Non-System Objects in master Database
-- Checklist:    3.6
-- Min Version:  SQL Server 2016 (v13)
-- Description:  Lists user-created objects (tables, stored procedures,
--               functions, views, triggers, etc.) found in the master database.
--               Objects stored in master are a governance and stability risk:
--                 - They survive individual database drops and restores.
--                 - They may conflict with Microsoft patch scripts or future
--                   SQL Server versions that introduce objects of the same name.
--                 - They fall outside normal application change control.
--                 - Stored procedures whose name begins with sp_ run in master
--                   context first, which can cause unexpected behaviour.
--
--               Common legitimate exceptions (document and accept if present):
--                 - Ola Hallengren / DBA maintenance stored procedures
--                   intentionally deployed to master so they are available
--                   from any database context.
--                 - Custom sp_WhoIsActive or similar DBA tooling.
--               If any objects are found, confirm they are intentional,
--               documented, and tracked in change control.
-- =============================================================================

IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning];
    RETURN;
END
GO

USE master;
GO

SET NOCOUNT ON;

SELECT
    CAST(SERVERPROPERTY('ServerName') AS SYSNAME)   AS SQLServer,
    s.name                                           AS SchemaName,
    o.name                                           AS ObjectName,
    o.type_desc                                      AS ObjectType,
    o.create_date                                    AS CreateDate,
    o.modify_date                                    AS ModifyDate,
    OBJECT_DEFINITION(o.object_id)                   AS ObjectDefinition
FROM sys.objects  o
JOIN sys.schemas  s ON s.schema_id = o.schema_id
WHERE o.is_ms_shipped = 0
  AND o.type NOT IN ('S', 'IT', 'SQ')   -- exclude system tables, internal tables, service queues
  AND s.name NOT IN ('sys', 'INFORMATION_SCHEMA')
ORDER BY o.type_desc, s.name, o.name;
