-- =============================================================================
-- Chapter:      11 — Index Health
-- Section:      11.07 — Unindexed Foreign Keys
-- Checklist:    11.7
-- Min Version:  SQL Server 2016 (v13)
-- Description:  Two checks per user database:
--                 1. UNINDEXED_FK — foreign key columns where the first FK
--                    column is not the leading key column of any index on the
--                    child table. SQL Server must do a full or partial scan to
--                    enforce referential integrity on parent UPDATE/DELETE, and
--                    the query optimiser cannot use an index seek for FK-driven
--                    JOINs. Each unindexed FK is a potential lock escalation
--                    and performance hotspot under concurrent DML.
--                 2. FK_REFS_UNIQUE_NOT_PK — foreign keys that reference a
--                    UNIQUE constraint rather than a PRIMARY KEY. Not a
--                    performance issue by itself, but an unusual design worth
--                    noting (commonly seen when the referenced table has no PK
--                    or the FK was intentionally pointed at a natural key).
--
-- NOTE: Not every unindexed FK warrants a new index. Before adding one:
--       - Verify the FK column has sufficient selectivity.
--       - Confirm the FK is exercised by DML against the parent table.
--       - Check whether the column already appears in another index at a
--         non-leading position that can still satisfy the lookup.
-- =============================================================================

IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning];
    RETURN;
END
GO

SET NOCOUNT ON;

DECLARE @DatabaseName  NVARCHAR(128);
DECLARE @Sql           NVARCHAR(MAX);

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM   sys.databases
    WHERE  state_desc  = 'ONLINE'
      AND  database_id > 4;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @DatabaseName;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- ── 1. FK columns without a leading index on the child table ─────────────
    SET @Sql = N'
USE ' + QUOTENAME(@DatabaseName) + N';

SELECT
    DB_NAME()                                               AS DatabaseName,
    ''UNINDEXED_FK''                                       AS CheckType,
    OBJECT_SCHEMA_NAME(fk.parent_object_id)                AS SchemaName,
    OBJECT_NAME(fk.parent_object_id)                       AS TableName,
    fk.name                                                 AS ForeignKeyName,
    OBJECT_SCHEMA_NAME(fk.referenced_object_id)            AS ReferencedSchema,
    OBJECT_NAME(fk.referenced_object_id)                   AS ReferencedTable,
    -- All FK columns in constraint order (comma-separated)
    STUFF((
        SELECT '','' + c.name
        FROM   sys.foreign_key_columns fkc2
        JOIN   sys.columns c
            ON  c.object_id = fkc2.parent_object_id
            AND c.column_id = fkc2.parent_column_id
        WHERE  fkc2.constraint_object_id = fk.object_id
        ORDER BY fkc2.constraint_column_id
        FOR XML PATH(''''), TYPE).value(''.'', ''NVARCHAR(MAX)''), 1, 1, '''')
                                                            AS FKColumns,
    -- Leading FK column that must be first in any covering index
    (SELECT c.name
     FROM   sys.foreign_key_columns fkc3
     JOIN   sys.columns c
         ON  c.object_id = fkc3.parent_object_id
         AND c.column_id = fkc3.parent_column_id
     WHERE  fkc3.constraint_object_id = fk.object_id
       AND  fkc3.constraint_column_id = 1)                 AS LeadingFKColumn,
    fk.is_disabled                                          AS IsDisabled
FROM sys.foreign_keys fk
WHERE OBJECTPROPERTY(fk.parent_object_id, ''IsMsShipped'') = 0
  -- Exclude FKs where the first FK column is the leading key of any index
  AND NOT EXISTS (
      SELECT 1
      FROM   sys.index_columns ic
      WHERE  ic.object_id          = fk.parent_object_id
        AND  ic.key_ordinal        = 1
        AND  ic.is_included_column = 0
        AND  ic.column_id = (
            SELECT fkc.parent_column_id
            FROM   sys.foreign_key_columns fkc
            WHERE  fkc.constraint_object_id = fk.object_id
              AND  fkc.constraint_column_id  = 1
        )
  )
ORDER BY OBJECT_SCHEMA_NAME(fk.parent_object_id),
         OBJECT_NAME(fk.parent_object_id),
         fk.name;
';
    EXEC sys.sp_executesql @Sql;

    -- ── 2. FK referencing a UNIQUE constraint instead of a PRIMARY KEY ────────
    SET @Sql = N'
USE ' + QUOTENAME(@DatabaseName) + N';

SELECT
    DB_NAME()                                               AS DatabaseName,
    ''FK_REFS_UNIQUE_NOT_PK''                              AS CheckType,
    OBJECT_SCHEMA_NAME(fk.parent_object_id)                AS SchemaName,
    OBJECT_NAME(fk.parent_object_id)                       AS TableName,
    fk.name                                                 AS ForeignKeyName,
    OBJECT_SCHEMA_NAME(fk.referenced_object_id)            AS ReferencedSchema,
    OBJECT_NAME(fk.referenced_object_id)                   AS ReferencedTable,
    kc.name                                                 AS ReferencedConstraintName,
    kc.type_desc                                            AS ReferencedConstraintType
FROM sys.foreign_keys   fk
JOIN sys.key_constraints kc
    ON  kc.parent_object_id = fk.referenced_object_id
    AND kc.unique_index_id  = fk.key_index_id
WHERE kc.type = ''UQ''    -- UQ = unique constraint; PK = primary key
ORDER BY OBJECT_SCHEMA_NAME(fk.parent_object_id),
         OBJECT_NAME(fk.parent_object_id),
         fk.name;
';
    EXEC sys.sp_executesql @Sql;

    FETCH NEXT FROM db_cursor INTO @DatabaseName;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;
