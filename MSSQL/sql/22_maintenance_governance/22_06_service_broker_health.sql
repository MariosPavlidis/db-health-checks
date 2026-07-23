-- =============================================================================
-- Health Check: Ch 22 Maintenance and Operational Governance — 22.6 Service Broker
-- Checklist ref: Section 22.6
-- Min SQL version: SQL Server 2016
--
-- Result sets:
--   1. Database-level Broker state, queue state, and transmission backlog
--   2. User-defined Service Broker queue inventory
--   3. Transmission queue backlog grouped by status
--   4. Per-database collection errors
-- =============================================================================
SET NOCOUNT ON;

IF TRY_CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    SELECT
        'VERSION_GUARD' AS ResultSetName,
        'Requires SQL Server 2016 or later.' AS Note;
    RETURN;
END;

CREATE TABLE #BrokerDatabaseDetail
(
    DatabaseId                INT            NOT NULL PRIMARY KEY,
    DatabaseName              SYSNAME        NOT NULL,
    UserQueueCount            BIGINT         NOT NULL,
    DisabledReceiveQueueCount BIGINT         NOT NULL,
    DisabledEnqueueQueueCount BIGINT         NOT NULL,
    TransmissionQueueCount    BIGINT         NOT NULL,
    TransmissionErrorCount    BIGINT         NOT NULL,
    OldestTransmissionUtc     DATETIME       NULL,
    ConversationEndpointCount BIGINT         NOT NULL
);

CREATE TABLE #BrokerQueues
(
    DatabaseName                  SYSNAME        NOT NULL,
    QueueSchema                   SYSNAME        NOT NULL,
    QueueName                     SYSNAME        NOT NULL,
    IsActivationEnabled           BIT            NOT NULL,
    ActivationProcedure           NVARCHAR(776)  NULL,
    MaxReaders                    SMALLINT       NOT NULL,
    IsReceiveEnabled              BIT            NOT NULL,
    IsEnqueueEnabled              BIT            NOT NULL,
    IsRetentionEnabled            BIT            NOT NULL,
    IsPoisonMessageHandlingEnabled BIT           NOT NULL
);

CREATE TABLE #BrokerTransmissionStatus
(
    DatabaseName      SYSNAME        NOT NULL,
    TransmissionStatus NVARCHAR(4000) NOT NULL,
    MessageCount      BIGINT         NOT NULL,
    OldestEnqueueUtc  DATETIME       NOT NULL
);

CREATE TABLE #BrokerCollectionErrors
(
    DatabaseName SYSNAME         NOT NULL,
    ErrorNumber  INT             NOT NULL,
    ErrorMessage NVARCHAR(4000)  NOT NULL
);

DECLARE @DatabaseName SYSNAME;
DECLARE @Sql NVARCHAR(MAX);

DECLARE broker_database_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM sys.databases
    WHERE database_id <> 2
      AND state_desc = N'ONLINE'
      AND HAS_DBACCESS(name) = 1
    ORDER BY database_id;

OPEN broker_database_cursor;
FETCH NEXT FROM broker_database_cursor INTO @DatabaseName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @Sql = N'
USE ' + QUOTENAME(@DatabaseName) + N';

INSERT #BrokerDatabaseDetail
(
    DatabaseId, DatabaseName, UserQueueCount,
    DisabledReceiveQueueCount, DisabledEnqueueQueueCount,
    TransmissionQueueCount, TransmissionErrorCount,
    OldestTransmissionUtc, ConversationEndpointCount
)
SELECT
    DB_ID(),
    DB_NAME(),
    (SELECT COUNT_BIG(*) FROM sys.service_queues WHERE is_ms_shipped = 0),
    (SELECT COUNT_BIG(*) FROM sys.service_queues
     WHERE is_ms_shipped = 0 AND is_receive_enabled = 0),
    (SELECT COUNT_BIG(*) FROM sys.service_queues
     WHERE is_ms_shipped = 0 AND is_enqueue_enabled = 0),
    (SELECT COUNT_BIG(*) FROM sys.transmission_queue),
    (SELECT COUNT_BIG(*) FROM sys.transmission_queue
     WHERE NULLIF(LTRIM(RTRIM(transmission_status)), N'''') IS NOT NULL),
    (SELECT MIN(enqueue_time) FROM sys.transmission_queue),
    (SELECT COUNT_BIG(*) FROM sys.conversation_endpoints);

INSERT #BrokerQueues
(
    DatabaseName, QueueSchema, QueueName, IsActivationEnabled,
    ActivationProcedure, MaxReaders, IsReceiveEnabled, IsEnqueueEnabled,
    IsRetentionEnabled, IsPoisonMessageHandlingEnabled
)
SELECT
    DB_NAME(),
    SCHEMA_NAME(schema_id),
    name,
    is_activation_enabled,
    activation_procedure,
    max_readers,
    is_receive_enabled,
    is_enqueue_enabled,
    is_retention_enabled,
    is_poison_message_handling_enabled
FROM sys.service_queues
WHERE is_ms_shipped = 0;

INSERT #BrokerTransmissionStatus
    (DatabaseName, TransmissionStatus, MessageCount, OldestEnqueueUtc)
SELECT
    DB_NAME(),
    COALESCE(NULLIF(LTRIM(RTRIM(transmission_status)), N''''), N''PENDING_WITHOUT_ERROR''),
    COUNT_BIG(*),
    MIN(enqueue_time)
FROM sys.transmission_queue
GROUP BY COALESCE(NULLIF(LTRIM(RTRIM(transmission_status)), N''''), N''PENDING_WITHOUT_ERROR'');';

    BEGIN TRY
        EXEC sys.sp_executesql @Sql;
    END TRY
    BEGIN CATCH
        INSERT #BrokerCollectionErrors
            (DatabaseName, ErrorNumber, ErrorMessage)
        VALUES
            (@DatabaseName, ERROR_NUMBER(), ERROR_MESSAGE());
    END CATCH;

    FETCH NEXT FROM broker_database_cursor INTO @DatabaseName;
END;

CLOSE broker_database_cursor;
DEALLOCATE broker_database_cursor;

SELECT
    'SERVICE_BROKER_DATABASE_STATE'                      AS ResultSetName,
    d.database_id                                       AS DatabaseId,
    d.name                                              AS DatabaseName,
    d.state_desc                                        AS DatabaseState,
    d.service_broker_guid                               AS ServiceBrokerGuid,
    d.is_broker_enabled                                 AS IsBrokerEnabled,
    d.is_honor_broker_priority_on                       AS IsHonorBrokerPriorityOn,
    COALESCE(bd.UserQueueCount, 0)                      AS UserQueueCount,
    COALESCE(bd.DisabledReceiveQueueCount, 0)           AS DisabledReceiveQueueCount,
    COALESCE(bd.DisabledEnqueueQueueCount, 0)           AS DisabledEnqueueQueueCount,
    COALESCE(bd.TransmissionQueueCount, 0)              AS TransmissionQueueCount,
    COALESCE(bd.TransmissionErrorCount, 0)              AS TransmissionErrorCount,
    bd.OldestTransmissionUtc,
    CASE
        WHEN bd.OldestTransmissionUtc IS NULL THEN NULL
        ELSE DATEDIFF(MINUTE, bd.OldestTransmissionUtc, GETUTCDATE())
    END                                                 AS OldestTransmissionAgeMinutes,
    COALESCE(bd.ConversationEndpointCount, 0)           AS ConversationEndpointCount,
    CASE
        WHEN d.is_broker_enabled = 0
         AND COALESCE(bd.UserQueueCount, 0) > 0 THEN 1 ELSE 0
    END                                                 AS flag_broker_disabled_with_user_queues,
    CASE
        WHEN COALESCE(bd.DisabledReceiveQueueCount, 0) > 0
          OR COALESCE(bd.DisabledEnqueueQueueCount, 0) > 0 THEN 1 ELSE 0
    END                                                 AS flag_user_queue_disabled,
    CASE WHEN COALESCE(bd.TransmissionErrorCount, 0) > 0 THEN 1 ELSE 0 END
                                                        AS flag_transmission_errors,
    CASE
        WHEN bd.OldestTransmissionUtc IS NOT NULL
         AND DATEDIFF(MINUTE, bd.OldestTransmissionUtc, GETUTCDATE()) >= 60
            THEN 1 ELSE 0
    END                                                 AS flag_transmission_older_than_60min
FROM sys.databases AS d
LEFT JOIN #BrokerDatabaseDetail AS bd
    ON bd.DatabaseId = d.database_id
WHERE d.database_id <> 2
ORDER BY
    CASE
        WHEN d.is_broker_enabled = 1
          OR COALESCE(bd.UserQueueCount, 0) > 0
          OR COALESCE(bd.TransmissionQueueCount, 0) > 0 THEN 0 ELSE 1
    END,
    d.name;

SELECT
    'SERVICE_BROKER_QUEUES'                      AS ResultSetName,
    DatabaseName,
    QueueSchema,
    QueueName,
    IsActivationEnabled,
    ActivationProcedure,
    MaxReaders,
    IsReceiveEnabled,
    IsEnqueueEnabled,
    IsRetentionEnabled,
    IsPoisonMessageHandlingEnabled,
    CASE
        WHEN IsReceiveEnabled = 0 OR IsEnqueueEnabled = 0 THEN 1 ELSE 0
    END                                         AS flag_queue_disabled
FROM #BrokerQueues
ORDER BY DatabaseName, QueueSchema, QueueName;

SELECT
    'SERVICE_BROKER_TRANSMISSION_BACKLOG'        AS ResultSetName,
    DatabaseName,
    TransmissionStatus,
    MessageCount,
    OldestEnqueueUtc,
    DATEDIFF(MINUTE, OldestEnqueueUtc, GETUTCDATE())
                                                AS OldestMessageAgeMinutes,
    CASE
        WHEN TransmissionStatus <> N'PENDING_WITHOUT_ERROR' THEN 1 ELSE 0
    END                                         AS flag_transmission_error,
    CASE
        WHEN DATEDIFF(MINUTE, OldestEnqueueUtc, GETUTCDATE()) >= 60 THEN 1 ELSE 0
    END                                         AS flag_backlog_older_than_60min
FROM #BrokerTransmissionStatus
ORDER BY MessageCount DESC, OldestEnqueueUtc;

SELECT
    'SERVICE_BROKER_COLLECTION_ERRORS' AS ResultSetName,
    DatabaseName,
    ErrorNumber,
    ErrorMessage,
    CAST(1 AS BIT) AS flag_collection_failed
FROM #BrokerCollectionErrors
ORDER BY DatabaseName;

DROP TABLE #BrokerCollectionErrors;
DROP TABLE #BrokerTransmissionStatus;
DROP TABLE #BrokerQueues;
DROP TABLE #BrokerDatabaseDetail;
