-- =============================================================================
-- Health Check: Ch 22 Maintenance and Operational Governance — 22.7 Resource Governor
-- Checklist ref: Section 22.7
-- Min SQL version: SQL Server 2016
--
-- Compares stored and effective Resource Governor configuration and reports
-- resource-pool/workload-group runtime pressure since statistics were reset.
-- =============================================================================
SET NOCOUNT ON;

IF TRY_CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT
        'VERSION_GUARD' AS ResultSetName,
        'Requires SQL Server 2016 or later.' AS Note;
    RETURN;
END;

SELECT
    'RESOURCE_GOVERNOR_STATE'                          AS ResultSetName,
    c.is_enabled                                       AS StoredIsEnabled,
    dc.is_enabled                                      AS EffectiveIsEnabled,
    c.classifier_function_id                           AS StoredClassifierFunctionId,
    OBJECT_SCHEMA_NAME(c.classifier_function_id, DB_ID(N'master'))
                                                       AS StoredClassifierSchema,
    OBJECT_NAME(c.classifier_function_id, DB_ID(N'master'))
                                                       AS StoredClassifierFunction,
    dc.classifier_function_id                          AS EffectiveClassifierFunctionId,
    OBJECT_SCHEMA_NAME(dc.classifier_function_id, DB_ID(N'master'))
                                                       AS EffectiveClassifierSchema,
    OBJECT_NAME(dc.classifier_function_id, DB_ID(N'master'))
                                                       AS EffectiveClassifierFunction,
    c.max_outstanding_io_per_volume                    AS StoredMaxOutstandingIoPerVolume,
    dc.max_outstanding_io_per_volume                   AS EffectiveMaxOutstandingIoPerVolume,
    (SELECT COUNT(*)
     FROM sys.resource_governor_resource_pools
     WHERE pool_id > 2)                                AS CustomResourcePoolCount,
    (SELECT COUNT(*)
     FROM sys.resource_governor_workload_groups
     WHERE group_id > 2)                               AS CustomWorkloadGroupCount,
    CASE
        WHEN c.is_enabled <> dc.is_enabled
          OR c.classifier_function_id <> dc.classifier_function_id
          OR c.max_outstanding_io_per_volume <> dc.max_outstanding_io_per_volume
            THEN 1 ELSE 0
    END                                                AS flag_reconfigure_pending,
    CASE
        WHEN c.is_enabled = 0
         AND
         (
             EXISTS (SELECT 1 FROM sys.resource_governor_resource_pools WHERE pool_id > 2)
             OR EXISTS (SELECT 1 FROM sys.resource_governor_workload_groups WHERE group_id > 2)
         )
            THEN 1 ELSE 0
    END                                                AS flag_custom_configuration_disabled,
    CASE
        WHEN dc.is_enabled = 1
         AND dc.classifier_function_id = 0
         AND EXISTS
             (
                 SELECT 1
                 FROM sys.resource_governor_workload_groups
                 WHERE group_id > 2
             )
            THEN 1 ELSE 0
    END                                                AS flag_enabled_without_classifier
FROM sys.resource_governor_configuration AS c
CROSS JOIN sys.dm_resource_governor_configuration AS dc;

SELECT
    'RESOURCE_GOVERNOR_POOLS'                           AS ResultSetName,
    p.pool_id                                           AS PoolId,
    p.name                                              AS PoolName,
    p.min_cpu_percent                                   AS StoredMinCpuPercent,
    p.max_cpu_percent                                   AS StoredMaxCpuPercent,
    p.cap_cpu_percent                                   AS StoredCapCpuPercent,
    p.min_memory_percent                                AS StoredMinMemoryPercent,
    p.max_memory_percent                                AS StoredMaxMemoryPercent,
    p.min_iops_per_volume                               AS StoredMinIopsPerVolume,
    p.max_iops_per_volume                               AS StoredMaxIopsPerVolume,
    dp.statistics_start_time                            AS StatisticsStartTime,
    dp.total_cpu_usage_ms                               AS TotalCpuUsageMs,
    dp.cache_memory_kb                                  AS CacheMemoryKB,
    dp.compile_memory_kb                                AS CompileMemoryKB,
    dp.used_memgrant_kb                                 AS UsedMemoryGrantKB,
    dp.total_memgrant_count                             AS TotalMemoryGrantCount,
    dp.total_memgrant_timeout_count                     AS TotalMemoryGrantTimeoutCount,
    dp.memgrant_waiter_count                            AS MemoryGrantWaiterCount,
    dp.used_memory_kb                                   AS UsedMemoryKB,
    dp.target_memory_kb                                 AS TargetMemoryKB,
    dp.out_of_memory_count                              AS OutOfMemoryCount,
    dp.read_io_throttled_total                          AS ReadIoThrottledTotal,
    dp.write_io_throttled_total                         AS WriteIoThrottledTotal,
    CASE WHEN dp.out_of_memory_count > 0 THEN 1 ELSE 0 END
                                                        AS flag_out_of_memory,
    CASE WHEN dp.total_memgrant_timeout_count > 0 THEN 1 ELSE 0 END
                                                        AS flag_memory_grant_timeouts,
    CASE WHEN dp.memgrant_waiter_count > 0 THEN 1 ELSE 0 END
                                                        AS flag_current_memory_grant_waiters,
    CASE
        WHEN COALESCE(dp.read_io_throttled_total, 0)
           + COALESCE(dp.write_io_throttled_total, 0) > 0 THEN 1 ELSE 0
    END                                                AS flag_io_throttling_observed
FROM sys.resource_governor_resource_pools AS p
LEFT JOIN sys.dm_resource_governor_resource_pools AS dp
    ON dp.pool_id = p.pool_id
ORDER BY p.pool_id;

SELECT
    'RESOURCE_GOVERNOR_WORKLOAD_GROUPS'                 AS ResultSetName,
    g.group_id                                          AS GroupId,
    g.name                                              AS WorkloadGroupName,
    p.name                                              AS ResourcePoolName,
    g.importance                                        AS StoredImportance,
    g.request_max_memory_grant_percent                  AS StoredMaxMemoryGrantPercent,
    g.request_max_cpu_time_sec                          AS StoredMaxCpuTimeSeconds,
    g.request_memory_grant_timeout_sec                  AS StoredMemoryGrantTimeoutSeconds,
    g.max_dop                                           AS StoredMaxDop,
    g.group_max_requests                                AS StoredMaxConcurrentRequests,
    dg.statistics_start_time                            AS StatisticsStartTime,
    dg.total_request_count                              AS TotalRequestCount,
    dg.total_queued_request_count                       AS TotalQueuedRequestCount,
    dg.active_request_count                             AS ActiveRequestCount,
    dg.queued_request_count                             AS QueuedRequestCount,
    dg.total_cpu_limit_violation_count                  AS CpuLimitViolationCount,
    dg.total_cpu_usage_ms                               AS TotalCpuUsageMs,
    dg.max_request_cpu_time_ms                          AS MaxRequestCpuTimeMs,
    dg.blocked_task_count                               AS BlockedTaskCount,
    dg.total_reduced_memgrant_count                     AS ReducedMemoryGrantCount,
    dg.max_request_grant_memory_kb                      AS MaxRequestGrantMemoryKB,
    dg.effective_max_dop                                AS EffectiveMaxDop,
    CASE WHEN dg.queued_request_count > 0 THEN 1 ELSE 0 END
                                                        AS flag_current_queued_requests,
    CASE WHEN dg.total_queued_request_count > 0 THEN 1 ELSE 0 END
                                                        AS flag_queueing_observed,
    CASE WHEN dg.total_cpu_limit_violation_count > 0 THEN 1 ELSE 0 END
                                                        AS flag_cpu_limit_violations,
    CASE WHEN dg.total_reduced_memgrant_count > 0 THEN 1 ELSE 0 END
                                                        AS flag_reduced_memory_grants
FROM sys.resource_governor_workload_groups AS g
JOIN sys.resource_governor_resource_pools AS p
    ON p.pool_id = g.pool_id
LEFT JOIN sys.dm_resource_governor_workload_groups AS dg
    ON dg.group_id = g.group_id
ORDER BY g.pool_id, g.group_id;
