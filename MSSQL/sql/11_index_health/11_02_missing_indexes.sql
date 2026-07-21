-- =============================================================================
-- Chapter:      11 — Index Health
-- Section:      11.02 — Missing Index Recommendations
-- Checklist:    11.2
-- Min Version:  SQL Server 2016 (v13)
-- Description:  Queries the missing index DMVs to surface indexes that the
--               query optimizer believes would improve query performance.
--               Results are ranked by EstimatedImpactScore (seeks * cost *
--               impact), limited to user databases (database_id > 4).
--
-- NOTE: DMV-based missing index recommendations MUST be reviewed by a
-- qualified DBA before any index is created. The DMVs do NOT account for:
--   - Overlapping or redundant existing indexes
--   - Write amplification cost on high-DML tables
--   - Transient workloads that have since changed
--   - Whether the suggested columns are already covered by another index
-- These counters are reset every time SQL Server restarts or the database
-- is taken offline. Low-uptime servers will show incomplete data.
-- Never create indexes mechanically from this output alone.
-- =============================================================================

IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT 'Requires SQL Server 2016 or later' AS [Warning];
    RETURN;
END
GO

SET NOCOUNT ON;

SELECT
    DB_NAME(mid.database_id)                                              AS DatabaseName,
    mid.database_id                                                       AS DatabaseId,
    mid.object_id                                                         AS ObjectId,
    OBJECT_NAME(mid.object_id, mid.database_id)                          AS TableName,
    mid.equality_columns                                                  AS EqualityColumns,
    mid.inequality_columns                                                AS InequalityColumns,
    mid.included_columns                                                  AS IncludedColumns,
    migs.unique_compiles                                                  AS UniqueCompiles,
    migs.user_seeks                                                       AS UserSeeks,
    migs.user_scans                                                       AS UserScans,
    migs.avg_total_user_cost                                              AS AvgQueryCost,
    migs.avg_user_impact                                                  AS AvgImpactPct,
    migs.user_seeks * migs.avg_total_user_cost * migs.avg_user_impact
        / 100.0                                                           AS EstimatedImpactScore,
    migs.last_user_seek                                                   AS LastUserSeek
FROM sys.dm_db_missing_index_details    mid
JOIN sys.dm_db_missing_index_groups     mig
    ON  mig.index_handle       = mid.index_handle
JOIN sys.dm_db_missing_index_group_stats migs
    ON  migs.group_handle      = mig.index_group_handle
WHERE mid.database_id > 4
ORDER BY EstimatedImpactScore DESC;
