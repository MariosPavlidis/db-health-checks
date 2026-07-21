# SQL Server Health Check Checklist

## Scope

This checklist is designed for execution by the customer. It collects configuration, operational, performance, security, storage, backup, integrity, SQL Agent, Windows, virtualization, WSFC, and Availability Group evidence.

The checklist does not include:

- Restore testing
- Point-in-time recovery testing
- Failover testing
- Failback testing
- Intrusive workload changes
- Production configuration changes
- Application code changes

Each task should produce exportable output in CSV, Excel, text, JSON, or PowerShell format.

---

# 1. Server Hardware, CPU, NUMA, and Memory

## 1.1 CPU and NUMA topology

- [ ] Collect logical CPU count
- [ ] Collect physical core count
- [ ] Collect socket count
- [ ] Collect cores per socket
- [ ] Collect hyperthreading ratio
- [ ] Collect physical NUMA node count
- [ ] Collect SQL Server soft-NUMA configuration
- [ ] Collect scheduler count per NUMA node
- [ ] Collect total scheduler count
- [ ] Collect visible online schedulers
- [ ] Collect hidden and background schedulers
- [ ] Collect processor group configuration
- [ ] Collect scheduler-to-memory-node mapping
- [ ] Identify uneven CPU distribution across physical NUMA nodes
- [ ] Identify uneven soft-NUMA scheduler distribution
- [ ] Validate vNUMA alignment with guest-visible NUMA topology

## 1.2 Scheduler health

- [ ] Collect current tasks per scheduler or NUMA node
- [ ] Collect runnable task count
- [ ] Collect work queue depth
- [ ] Collect pending disk I/O
- [ ] Collect active worker count
- [ ] Collect idle scheduler count
- [ ] Check for sustained runnable queues
- [ ] Check for scheduler imbalance
- [ ] Check for worker thread exhaustion
- [ ] Check for THREADPOOL waits

## 1.3 Parallelism configuration

- [ ] Collect instance MAXDOP
- [ ] Collect database-scoped MAXDOP
- [ ] Collect Cost Threshold for Parallelism
- [ ] Validate MAXDOP against NUMA layout
- [ ] Check for excessive CXPACKET waits
- [ ] Check for excessive CXCONSUMER waits
- [ ] Check for forced serialization
- [ ] Check for serial-plan bottlenecks
- [ ] Check for queries with excessive parallelism
- [ ] Check for databases with workload-specific MAXDOP requirements

## 1.4 SQL Server memory configuration

- [ ] Collect total physical memory
- [ ] Collect available physical memory
- [ ] Collect SQL Server physical memory usage
- [ ] Collect min server memory
- [ ] Collect max server memory
- [ ] Collect memory utilization percentage
- [ ] Collect virtual address space committed
- [ ] Collect SQL Server memory model
- [ ] Collect Locked Pages in Memory status
- [ ] Collect Large Pages status
- [ ] Validate OS memory headroom
- [ ] Validate max server memory against total server workload
- [ ] Identify memory configuration changes not yet active

## 1.5 OS memory and paging

- [ ] Collect page file total size
- [ ] Collect page file used space
- [ ] Collect page file free space
- [ ] Collect page file utilization percentage
- [ ] Collect page fault count
- [ ] Collect available page file
- [ ] Collect Windows memory pressure state
- [ ] Check for working set trimming
- [ ] Check for sustained paging activity
- [ ] Check for memory ballooning evidence
- [ ] Check for dynamic memory configuration
- [ ] Check for host memory overcommitment evidence

## 1.6 SQL Server memory internals

- [ ] Collect top memory clerks
- [ ] Collect buffer pool allocation
- [ ] Collect plan cache allocation
- [ ] Collect lock manager memory
- [ ] Collect query memory usage
- [ ] Collect CLR memory usage
- [ ] Collect per-NUMA memory allocation
- [ ] Collect foreign NUMA memory
- [ ] Collect local NUMA memory
- [ ] Identify uneven memory distribution
- [ ] Check for memory grants pending
- [ ] Check RESOURCE_SEMAPHORE waits
- [ ] Check excessive memory grants
- [ ] Check underused memory grants

## 1.7 Power and processor configuration

- [ ] Collect Windows power plan
- [ ] Validate High Performance or approved equivalent
- [ ] Check CPU frequency throttling
- [ ] Check hypervisor host power policy
- [ ] Check CPU hot-add configuration
- [ ] Check memory hot-add configuration

---

# 2. Virtualization and Hypervisor

## 2.1 Guest-visible virtualization checks

- [ ] Identify hypervisor platform
- [ ] Collect VM vCPU count
- [ ] Collect virtual sockets
- [ ] Collect virtual cores per socket
- [ ] Collect guest-visible NUMA topology
- [ ] Collect VM memory size
- [ ] Identify dynamic memory
- [ ] Identify CPU hot-add
- [ ] Identify memory hot-add
- [ ] Identify virtual storage controller type
- [ ] Identify VM snapshots visible to the guest
- [ ] Check time synchronization source
- [ ] Check NTP drift

## 2.2 Hypervisor-side evidence

- [ ] Collect CPU ready time
- [ ] Collect co-stop or equivalent scheduling delay
- [ ] Collect memory ballooning
- [ ] Collect memory swapping
- [ ] Collect host CPU overcommitment ratio
- [ ] Collect host memory overcommitment ratio
- [ ] Collect VM NUMA placement
- [ ] Collect host storage latency
- [ ] Collect datastore latency
- [ ] Collect snapshot inventory
- [ ] Collect virtual disk queue metrics
- [ ] Collect host power policy
- [ ] Identify noisy-neighbor conditions

---

# 3. SQL Server Instance Configuration

## 3.1 Instance identity and platform

- [ ] Collect instance name
- [ ] Collect machine name
- [ ] Collect SQL Server version
- [ ] Collect build number
- [ ] Collect edition
- [ ] Collect licensing model
- [ ] Collect Windows version
- [ ] Collect Windows build
- [ ] Collect OS language
- [ ] Collect SQL Server collation
- [ ] Collect instance start time
- [ ] Collect last restart reason
- [ ] Collect clustered instance status
- [ ] Collect HADR enabled status
- [ ] Collect XTP support status

## 3.2 Patch and support level

- [ ] Collect current SQL Server CU or GDR
- [ ] Compare against approved patch baseline
- [ ] Collect Windows patch level
- [ ] Check SQL Server and OS support status
- [ ] Check patch consistency across AG replicas
- [ ] Check patch consistency across WSFC nodes
- [ ] Identify pending reboot state
- [ ] Identify failed SQL Server patch attempts
- [ ] Identify failed Windows update attempts

## 3.3 SQL Server services

- [ ] Collect SQL Server service state
- [ ] Collect SQL Server Agent service state
- [ ] Collect SQL Browser state
- [ ] Collect SQL Writer state
- [ ] Collect startup type
- [ ] Collect service accounts
- [ ] Validate use of dedicated service accounts
- [ ] Check service account local administrator membership
- [ ] Check service account interactive logon rights
- [ ] Check required service account privileges
- [ ] Check service account password or gMSA status
- [ ] Check service account SPNs
- [ ] Check Kerberos authentication status

## 3.4 Instance configuration options

- [ ] Export all sys.configurations values
- [ ] Compare configured and running values
- [ ] Collect backup compression default
- [ ] Collect optimize for ad hoc workloads
- [ ] Collect remote admin connections
- [ ] Collect max worker threads
- [ ] Collect network packet size
- [ ] Collect remote query timeout
- [ ] Collect blocked process threshold
- [ ] Collect query governor cost limit
- [ ] Collect ad hoc distributed queries
- [ ] Collect CLR enabled status
- [ ] Collect contained database authentication
- [ ] Collect default trace status
- [ ] Collect Database Mail XPs status
- [ ] Collect Agent XPs status
- [ ] Collect startup parameters
- [ ] Collect startup trace flags
- [ ] Identify obsolete trace flags
- [ ] Identify unsupported trace flags
- [ ] Identify undocumented trace flags
- [ ] Identify configuration deviations from baseline

## 3.5 Default paths and logs

- [ ] Collect default data path
- [ ] Collect default log path
- [ ] Collect default backup path
- [ ] Collect SQL Server error log path
- [ ] Collect SQL Agent log path
- [ ] Collect number of retained SQL Server error logs
- [ ] Collect number of retained SQL Agent logs
- [ ] Validate error log cycling frequency
- [ ] Check oversized error logs
- [ ] Check startup procedure configuration
- [ ] Review active Extended Events sessions

---

# 4. Database Inventory and Configuration

## 4.1 Database inventory

- [ ] Collect all databases
- [ ] Collect database IDs
- [ ] Collect creation dates
- [ ] Collect database state
- [ ] Collect online, offline, restoring, recovery pending, suspect, and emergency states
- [ ] Collect user access mode
- [ ] Collect read-only status
- [ ] Collect database owner
- [ ] Collect database collation
- [ ] Collect containment type
- [ ] Collect compatibility level
- [ ] Collect recovery model
- [ ] Collect AG membership
- [ ] Collect replication participation
- [ ] Collect CDC status
- [ ] Collect Change Tracking status
- [ ] Collect Service Broker status
- [ ] Collect FILESTREAM or FileTable usage
- [ ] Collect In-Memory OLTP usage
- [ ] Collect temporal table usage

## 4.2 Database options

- [ ] Collect AUTO_CLOSE
- [ ] Collect AUTO_SHRINK
- [ ] Collect AUTO_CREATE_STATISTICS
- [ ] Collect AUTO_UPDATE_STATISTICS
- [ ] Collect AUTO_UPDATE_STATISTICS_ASYNC
- [ ] Collect PAGE_VERIFY
- [ ] Collect READ_COMMITTED_SNAPSHOT
- [ ] Collect ALLOW_SNAPSHOT_ISOLATION
- [ ] Collect TARGET_RECOVERY_TIME
- [ ] Collect DELAYED_DURABILITY
- [ ] Collect PARAMETERIZATION mode
- [ ] Collect TRUSTWORTHY
- [ ] Collect DB_CHAINING
- [ ] Collect recursive triggers
- [ ] Collect broker enabled status
- [ ] Collect database ownership chaining
- [ ] Collect guest user access
- [ ] Collect database-scoped configurations
- [ ] Collect legacy cardinality estimator setting
- [ ] Collect parameter sniffing setting
- [ ] Collect scalar UDF inlining
- [ ] Collect batch mode on rowstore
- [ ] Collect automatic tuning
- [ ] Collect Accelerated Database Recovery
- [ ] Collect Persistent Version Store status

## 4.3 Query Store configuration

- [ ] Collect Query Store enabled status
- [ ] Collect Query Store operation mode
- [ ] Collect capture mode
- [ ] Collect current size
- [ ] Collect maximum size
- [ ] Collect cleanup mode
- [ ] Collect stale query threshold
- [ ] Collect interval length
- [ ] Collect wait statistics capture
- [ ] Identify Query Store read-only state
- [ ] Identify Query Store size pressure
- [ ] Identify Query Store cleanup failures
- [ ] Identify databases without Query Store where it would be beneficial

## 4.4 Database ownership and collation

- [ ] Identify databases owned by personal accounts
- [ ] Identify databases owned by disabled logins
- [ ] Identify database and server collation differences
- [ ] Identify cross-database collation conflicts
- [ ] Identify databases with non-standard compatibility levels
- [ ] Identify databases with legacy recovery settings

## 4.5 Table and object size inventory

- [ ] Collect top tables by total size
- [ ] Collect top tables by row count
- [ ] Collect heap size
- [ ] Collect clustered index size
- [ ] Collect nonclustered index size
- [ ] Collect LOB size
- [ ] Collect FILESTREAM size
- [ ] Identify unusually large logging tables
- [ ] Identify archive tables
- [ ] Identify staging tables
- [ ] Identify tables with dates in their names
- [ ] Identify likely backup or copied tables
- [ ] Identify large unused or obsolete tables
- [ ] Identify tables affecting backup, restore, and maintenance duration

---

# 5. Storage, Volumes, Files, and I/O

## 5.1 Volume capacity

- [ ] Collect volume name
- [ ] Collect volume label
- [ ] Collect mount point
- [ ] Collect total size
- [ ] Collect used space
- [ ] Collect free space
- [ ] Collect free percentage
- [ ] Map volumes to SQL Server purpose
- [ ] Identify low-free-space volumes
- [ ] Identify volumes close to operational threshold
- [ ] Identify shared data and log volumes
- [ ] Identify shared SQL Server and non-SQL workloads
- [ ] Identify mount points not monitored

## 5.2 File inventory

- [ ] Collect all database files
- [ ] Collect logical file name
- [ ] Collect physical file path
- [ ] Collect file type
- [ ] Collect filegroup
- [ ] Collect current size
- [ ] Collect used space
- [ ] Collect free internal space
- [ ] Collect growth setting
- [ ] Collect percentage-growth configuration
- [ ] Collect maximum size
- [ ] Collect file state
- [ ] Collect sparse-file status
- [ ] Identify files with unlimited growth
- [ ] Identify files near maximum size
- [ ] Identify files with small fixed growth
- [ ] Identify files using percentage growth
- [ ] Identify files on incorrect storage tiers
- [ ] Identify data and log placement conflicts

## 5.3 Autogrowth and shrink history

- [ ] Collect data-file autogrowth events
- [ ] Collect log-file autogrowth events
- [ ] Collect autogrowth frequency
- [ ] Collect autogrowth duration
- [ ] Collect autogrowth size
- [ ] Identify repeated small autogrowth events
- [ ] Identify growth during peak workload
- [ ] Collect shrink events
- [ ] Identify scheduled shrink jobs
- [ ] Identify recurring grow-shrink cycles
- [ ] Recommend proactive file sizing where justified

## 5.4 Disk allocation and sector size

- [ ] Collect allocation unit size for SQL Server volumes
- [ ] Identify 4 KB allocation units
- [ ] Identify volumes not aligned with approved standards
- [ ] Collect physical sector size
- [ ] Collect logical sector size
- [ ] Identify unsupported sector-size configurations
- [ ] Collect storage controller information
- [ ] Validate mount-point and volume configuration

## 5.5 File-level I/O latency

- [ ] Collect reads per file
- [ ] Collect writes per file
- [ ] Collect bytes read
- [ ] Collect bytes written
- [ ] Collect cumulative read stall
- [ ] Collect cumulative write stall
- [ ] Calculate average read latency
- [ ] Calculate average write latency
- [ ] Calculate average total latency
- [ ] Compare data-file and log-file latency
- [ ] Identify high-latency files
- [ ] Identify idle files with misleading averages
- [ ] Collect interval-based I/O deltas
- [ ] Identify latency trends

## 5.6 Storage subsystem evidence

- [ ] Collect disk queue depth
- [ ] Collect IOPS
- [ ] Collect throughput
- [ ] Collect storage path count
- [ ] Collect MPIO state
- [ ] Collect iSCSI state
- [ ] Collect path failover events
- [ ] Collect controller cache mode
- [ ] Validate write-cache protection
- [ ] Collect SAN or storage-tier details
- [ ] Identify throttling
- [ ] Identify storage saturation
- [ ] Identify cross-host or cross-datastore contention

## 5.7 Instant File Initialization

- [ ] Collect Instant File Initialization status
- [ ] Validate Perform Volume Maintenance Tasks privilege
- [ ] Identify SQL Server service accounts missing the privilege
- [ ] Confirm that the recommendation applies only to data-file initialization
- [ ] Exclude transaction-log growth from IFI conclusions

---

# 6. TempDB

## 6.1 TempDB configuration

- [ ] Collect TempDB data-file count
- [ ] Collect TempDB log-file count
- [ ] Collect file sizes
- [ ] Collect file growth settings
- [ ] Collect maximum file size
- [ ] Validate equal data-file sizing
- [ ] Validate equal growth settings
- [ ] Identify recently added undersized files
- [ ] Validate TempDB file placement
- [ ] Validate TempDB pre-sizing

## 6.2 TempDB capacity and usage

- [ ] Collect TempDB total size
- [ ] Collect TempDB free space
- [ ] Collect user-object usage
- [ ] Collect internal-object usage
- [ ] Collect version-store usage
- [ ] Collect Persistent Version Store usage
- [ ] Collect session-level TempDB usage
- [ ] Collect task-level TempDB usage
- [ ] Identify top TempDB-consuming sessions
- [ ] Identify top TempDB-consuming queries
- [ ] Identify version-store retention caused by long transactions

## 6.3 TempDB performance

- [ ] Collect TempDB read latency
- [ ] Collect TempDB write latency
- [ ] Collect TempDB log latency
- [ ] Check PAGELATCH contention
- [ ] Check PFS contention
- [ ] Check GAM contention
- [ ] Check SGAM contention
- [ ] Check metadata contention
- [ ] Check sort spills
- [ ] Check hash spills
- [ ] Check worktable and workfile activity
- [ ] Check TempDB autogrowth history
- [ ] Check TempDB out-of-space events

---

# 7. Transaction Log Health

## 7.1 Log configuration

- [ ] Collect log-file size
- [ ] Collect log-file used space
- [ ] Collect log-file free space
- [ ] Collect log growth setting
- [ ] Collect log maximum size
- [ ] Collect recovery model
- [ ] Collect log reuse wait
- [ ] Collect active log size
- [ ] Collect inactive log size
- [ ] Collect log generated since last backup
- [ ] Collect last log backup size
- [ ] Identify oversized log files
- [ ] Identify undersized log files
- [ ] Identify log files sharing storage with data files

## 7.2 VLF health

- [ ] Collect total VLF count
- [ ] Collect active VLF count
- [ ] Collect inactive VLF count
- [ ] Collect VLF size distribution
- [ ] Collect VLF creation sequence
- [ ] Identify excessive VLF counts
- [ ] Identify many very small VLFs
- [ ] Identify poor autogrowth history
- [ ] Estimate recovery impact
- [ ] Recommend log re-sizing only where justified

## 7.3 Log reuse and truncation

- [ ] Identify databases waiting on LOG_BACKUP
- [ ] Identify databases waiting on ACTIVE_TRANSACTION
- [ ] Identify databases waiting on AVAILABILITY_REPLICA
- [ ] Identify databases waiting on REPLICATION
- [ ] Identify databases waiting on OLDEST_PAGE
- [ ] Identify databases waiting on DATABASE_SNAPSHOT_CREATION
- [ ] Identify log truncation blockers
- [ ] Identify databases in FULL recovery without log backups
- [ ] Identify abnormal log growth risk

## 7.4 Log backup behavior

- [ ] Collect last log backup
- [ ] Collect log backup frequency
- [ ] Collect log backup duration
- [ ] Collect log backup size
- [ ] Collect log backup compression
- [ ] Collect largest historical gap
- [ ] Identify missed schedules
- [ ] Identify failed log backup jobs
- [ ] Estimate backup-based RPO exposure

---

# 8. Performance Baseline

## 8.1 Wait statistics

- [ ] Collect instance wait statistics
- [ ] Record SQL Server restart time
- [ ] Exclude benign or idle waits
- [ ] Calculate wait percentage
- [ ] Calculate average wait duration
- [ ] Calculate signal wait time
- [ ] Calculate resource wait time
- [ ] Collect interval-based wait deltas
- [ ] Identify CPU pressure waits
- [ ] Identify I/O waits
- [ ] Identify lock waits
- [ ] Identify log waits
- [ ] Identify memory waits
- [ ] Identify network waits
- [ ] Identify backup waits
- [ ] Identify AG waits
- [ ] Identify parallelism waits
- [ ] Identify worker-thread waits
- [ ] Identify external-resource waits

## 8.2 Core workload counters

- [ ] Collect batch requests per second
- [ ] Collect transactions per second
- [ ] Collect compilations per second
- [ ] Collect recompilations per second
- [ ] Collect page reads per second
- [ ] Collect page writes per second
- [ ] Collect lazy writes per second
- [ ] Collect checkpoint pages per second
- [ ] Collect log flushes per second
- [ ] Collect log bytes flushed per second
- [ ] Collect connection count
- [ ] Collect login rate
- [ ] Collect logout rate
- [ ] Collect blocked process count
- [ ] Collect deadlock rate
- [ ] Collect memory grants pending
- [ ] Collect target and total server memory
- [ ] Collect buffer cache metrics
- [ ] Collect Page Life Expectancy as a trend, not a fixed threshold

## 8.3 CPU and worker analysis

- [ ] Collect SQL Server CPU utilization
- [ ] Collect OS CPU utilization
- [ ] Collect CPU utilization by hour
- [ ] Collect CPU utilization by NUMA node
- [ ] Collect runnable scheduler count
- [ ] Identify sustained CPU saturation
- [ ] Identify high signal-wait percentage
- [ ] Identify worker exhaustion
- [ ] Identify login storms
- [ ] Identify connection-pool pressure

## 8.4 Memory and plan cache

- [ ] Collect plan cache size
- [ ] Collect single-use ad hoc plans
- [ ] Collect multi-use plans
- [ ] Identify ad hoc plan cache bloat
- [ ] Check optimize for ad hoc workloads
- [ ] Collect plan eviction indicators
- [ ] Collect memory grant usage
- [ ] Collect pending memory grants
- [ ] Identify over-granted queries
- [ ] Identify spill-prone queries
- [ ] Identify memory pressure trends

---

# 9. Query Store and Query Performance

## 9.1 Query Store waits

- [ ] Collect waits by database
- [ ] Collect waits by category
- [ ] Collect total wait time
- [ ] Collect average wait time
- [ ] Collect affected query count
- [ ] Identify lock-heavy queries
- [ ] Identify I/O-heavy queries
- [ ] Identify memory-heavy queries
- [ ] Identify network-heavy queries
- [ ] Identify parallelism-heavy queries
- [ ] Identify log-write-heavy queries

## 9.2 Top resource-consuming queries

- [ ] Collect top queries by total duration
- [ ] Collect top queries by average duration
- [ ] Collect top queries by CPU
- [ ] Collect top queries by logical reads
- [ ] Collect top queries by physical reads
- [ ] Collect top queries by writes
- [ ] Collect top queries by execution count
- [ ] Collect top queries by memory grant
- [ ] Collect top queries by TempDB usage
- [ ] Collect top queries by lock wait
- [ ] Collect top queries by network wait
- [ ] Collect minimum duration
- [ ] Collect maximum duration
- [ ] Collect execution count
- [ ] Collect average rows
- [ ] Collect average logical reads
- [ ] Collect plan IDs
- [ ] Collect query IDs

## 9.3 Query regression and plan stability

- [ ] Identify regressed queries
- [ ] Identify queries with multiple plans
- [ ] Identify forced plans
- [ ] Identify failed forced plans
- [ ] Identify plan forcing failures
- [ ] Identify high plan variance
- [ ] Identify parameter-sensitive queries
- [ ] Identify plan-cache instability
- [ ] Identify sudden duration regressions
- [ ] Identify sudden CPU regressions
- [ ] Identify sudden I/O regressions

## 9.4 Execution plan warnings

- [ ] Identify implicit conversions
- [ ] Identify non-SARGable predicates
- [ ] Identify missing join predicates
- [ ] Identify spills to TempDB
- [ ] Identify excessive memory grants
- [ ] Identify key lookups
- [ ] Identify residual predicates
- [ ] Identify scans on large tables
- [ ] Identify cardinality-estimation errors
- [ ] Identify forced serialization
- [ ] Identify scalar UDF bottlenecks
- [ ] Identify row-goal issues
- [ ] Identify excessive parallelism
- [ ] Identify plan warnings
- [ ] Identify cursor-heavy execution patterns

---

# 10. Blocking, Locking, and Deadlocks

## 10.1 Blocking analysis

- [ ] Collect current blocking chains
- [ ] Collect head blockers
- [ ] Collect blocked sessions
- [ ] Collect blocking duration
- [ ] Collect lock types
- [ ] Collect locked objects
- [ ] Collect transaction start time
- [ ] Collect session application name
- [ ] Collect client host
- [ ] Collect login name
- [ ] Collect SQL text
- [ ] Collect execution plan
- [ ] Identify sleeping sessions with open transactions
- [ ] Identify long-running open transactions
- [ ] Identify recurring blocked objects
- [ ] Identify blocking caused by maintenance
- [ ] Identify blocking caused by cursors
- [ ] Identify blocking caused by lock escalation

## 10.2 Lock escalation

- [ ] Collect lock escalation events
- [ ] Identify statements touching more than escalation thresholds
- [ ] Identify table-level locks
- [ ] Identify large updates and deletes
- [ ] Identify missing indexes causing large lock footprints
- [ ] Identify cursor-driven cumulative row locking
- [ ] Identify lock escalation on partitioned tables
- [ ] Recommend batching where justified
- [ ] Recommend indexing where justified

## 10.3 Deadlock history

- [ ] Collect deadlock graphs
- [ ] Collect deadlocks per day
- [ ] Collect deadlocks by database
- [ ] Collect deadlocks by table
- [ ] Collect deadlocks by statement
- [ ] Collect deadlocks by application
- [ ] Collect deadlocks by login
- [ ] Collect deadlocks by host
- [ ] Identify recurring deadlock signatures
- [ ] Identify cursor involvement
- [ ] Identify conflicting access order
- [ ] Identify conversion deadlocks
- [ ] Identify key lookup deadlocks
- [ ] Identify parallelism deadlocks
- [ ] Identify application transaction-scope issues
- [ ] Identify deadlock spikes after incidents or restarts

## 10.4 Extended Events readiness

- [ ] Check active deadlock capture
- [ ] Check system_health retention
- [ ] Check blocked process capture
- [ ] Check lock escalation capture
- [ ] Check session output path
- [ ] Check file rollover settings
- [ ] Check event retention mode
- [ ] Check for oversized or missing XE files

---

# 11. Index Health

## 11.1 Fragmentation

- [ ] Collect index fragmentation
- [ ] Collect page count
- [ ] Exclude very small indexes
- [ ] Identify heavily fragmented large indexes
- [ ] Identify partition-level fragmentation
- [ ] Compare fragmentation with workload and maintenance policy
- [ ] Check maintenance duration
- [ ] Check fragmentation recurrence
- [ ] Avoid automatic rebuild recommendations based only on percentages

## 11.2 Missing indexes

- [ ] Collect missing-index DMV recommendations
- [ ] Collect estimated impact
- [ ] Collect user seeks
- [ ] Collect user scans
- [ ] Compare with existing indexes
- [ ] Consolidate overlapping recommendations
- [ ] Validate key-column order
- [ ] Validate include columns
- [ ] Check expected write overhead
- [ ] Check storage impact
- [ ] Check whether recommendation is based on transient workload
- [ ] Produce reviewed index proposals only

## 11.3 Unused indexes

- [ ] Collect index usage statistics
- [ ] Record SQL Server restart time
- [ ] Exclude primary keys
- [ ] Exclude unique constraints
- [ ] Exclude clustered indexes where required for storage
- [ ] Collect index size
- [ ] Collect write count
- [ ] Collect scan count
- [ ] Collect seek count
- [ ] Collect lookup count
- [ ] Identify indexes unused since restart
- [ ] Identify indexes unused across a full business cycle
- [ ] Identify large high-write unused indexes
- [ ] Avoid direct drop recommendations without validation

## 11.4 Duplicate and overlapping indexes

- [ ] Identify exact duplicate indexes
- [ ] Identify indexes with identical key columns
- [ ] Identify indexes with identical key and include columns
- [ ] Identify overlapping prefixes
- [ ] Identify duplicate unique indexes
- [ ] Identify redundant indexes duplicating primary keys
- [ ] Check filters
- [ ] Check sort direction
- [ ] Check partition scheme
- [ ] Check compression
- [ ] Recommend consolidation only after dependency validation

## 11.5 Additional index conditions

- [ ] Identify disabled indexes
- [ ] Identify hypothetical indexes
- [ ] Identify heaps
- [ ] Identify forwarded records
- [ ] Identify high page-split indexes
- [ ] Collect fill factor
- [ ] Collect OPTIMIZE_FOR_SEQUENTIAL_KEY
- [ ] Collect index compression
- [ ] Identify inconsistent partition compression
- [ ] Identify misaligned indexes
- [ ] Identify unused filtered indexes
- [ ] Identify indexed views and usage

## 11.6 Columnstore health

- [ ] Identify columnstore indexes
- [ ] Collect rowgroup state
- [ ] Collect open rowgroups
- [ ] Collect compressed rowgroups
- [ ] Collect deleted-row percentage
- [ ] Identify trim reasons
- [ ] Identify undersized rowgroups
- [ ] Identify dictionary pressure
- [ ] Identify tuple mover backlog
- [ ] Identify columnstore maintenance requirements

---

# 12. Statistics Health

## 12.1 Statistics inventory

- [ ] Collect statistics per table
- [ ] Collect auto-created statistics
- [ ] Collect index statistics
- [ ] Collect user-created statistics
- [ ] Collect filtered statistics
- [ ] Collect incremental statistics
- [ ] Collect persisted sample percentage

## 12.2 Statistics freshness

- [ ] Collect last update date
- [ ] Collect row count
- [ ] Collect modification counter
- [ ] Collect sample percentage
- [ ] Identify stale statistics
- [ ] Identify statistics on rapidly changing tables
- [ ] Identify ascending-key patterns
- [ ] Identify partition-level statistics issues
- [ ] Identify statistics maintenance gaps

## 12.3 Duplicate statistics

- [ ] Identify duplicate statistics on identical column sets
- [ ] Identify auto-created statistics overlapping index statistics
- [ ] Check filtered predicates
- [ ] Check statistics dependencies
- [ ] Check query plan usage
- [ ] Recommend removal only after validation
- [ ] Avoid automatic deletion based only on column overlap

---

# 13. Backup and Recovery Configuration

## 13.1 Backup coverage

- [ ] Collect last full backup
- [ ] Collect last differential backup
- [ ] Collect last log backup
- [ ] Collect backup duration
- [ ] Collect backup size
- [ ] Collect compressed size
- [ ] Collect backup location
- [ ] Collect copy-only status
- [ ] Collect checksum status
- [ ] Collect encryption status
- [ ] Collect backup software name
- [ ] Identify databases without current backups
- [ ] Identify FULL recovery databases without log backups
- [ ] Identify backup jobs that exclude databases
- [ ] Identify backup schedules inconsistent with database recovery model

## 13.2 Backup-chain and schedule consistency

- [ ] Collect first LSN
- [ ] Collect last LSN
- [ ] Collect checkpoint LSN
- [ ] Collect database backup LSN
- [ ] Collect differential base LSN
- [ ] Collect fork GUID
- [ ] Collect recovery fork
- [ ] Collect backup type
- [ ] Collect backup start and finish
- [ ] Identify unexpected log backup gaps
- [ ] Identify recovery-model changes
- [ ] Identify differential-base inconsistencies
- [ ] Identify copy-only full backups
- [ ] Identify incomplete msdb backup history
- [ ] State that this check does not validate backup-file usability

## 13.3 RPO historical compliance

- [ ] Collect configured log backup interval
- [ ] Calculate actual average log backup interval
- [ ] Calculate maximum observed log backup gap
- [ ] Identify missed backup windows
- [ ] Identify recent backup failures
- [ ] Identify current backup exposure
- [ ] Compare actual evidence with documented RPO
- [ ] Report estimated backup-based RPO
- [ ] Report AG-related data-loss indicators separately
- [ ] Avoid claiming guaranteed RPO

## 13.4 RTO risk indicators

- [ ] Collect database size
- [ ] Collect full backup duration
- [ ] Collect log backup volume
- [ ] Collect VLF count
- [ ] Collect recovery model
- [ ] Collect target recovery time
- [ ] Collect indirect checkpoint setting
- [ ] Collect AG failover mode
- [ ] Collect AG synchronization state
- [ ] Collect redo queue
- [ ] Collect estimated redo catch-up time
- [ ] Collect last startup recovery duration from error log where available
- [ ] Report RTO risk indicators
- [ ] State that actual RTO cannot be validated without recovery or failover testing

## 13.5 Backup retention and operations

- [ ] Collect backup retention period
- [ ] Collect backup cleanup jobs
- [ ] Collect failed cleanup jobs
- [ ] Identify backup accumulation on disk
- [ ] Identify backup copy jobs
- [ ] Identify disabled backup-copy jobs
- [ ] Identify stale backup files
- [ ] Identify backup target capacity risk
- [ ] Collect backup throughput
- [ ] Identify unusually slow backups
- [ ] Correlate backup waits with storage or network latency

---

# 14. Integrity and Corruption

## 14.1 DBCC CHECKDB

- [ ] Collect last CHECKDB execution per database
- [ ] Collect CHECKDB result
- [ ] Collect CHECKDB duration
- [ ] Collect CHECKDB job schedule
- [ ] Identify databases never checked
- [ ] Identify databases overdue for CHECKDB
- [ ] Identify CHECKDB jobs without schedules
- [ ] Identify CHECKDB failures
- [ ] Identify PHYSICAL_ONLY usage
- [ ] Identify full CHECKDB coverage
- [ ] Identify CHECKDB executed on another server where documented

## 14.2 SQL Server I/O and corruption errors

- [ ] Search SQL Server error logs for error 823
- [ ] Search SQL Server error logs for error 824
- [ ] Search SQL Server error logs for error 825
- [ ] Search SQL Server error logs for error 832
- [ ] Search SQL Server error logs for severity 20–25
- [ ] Search for checksum failures
- [ ] Search for torn-page errors
- [ ] Search for I/O retry warnings
- [ ] Search for failed database recovery
- [ ] Search for damaged backup warnings
- [ ] Correlate with Windows storage events

## 14.3 Suspect pages

- [ ] Export msdb.dbo.suspect_pages
- [ ] Collect database ID
- [ ] Collect file ID
- [ ] Collect page ID
- [ ] Collect event type
- [ ] Collect error count
- [ ] Collect last update date
- [ ] Translate event type
- [ ] Identify unresolved suspect pages
- [ ] Identify recurring page errors
- [ ] Identify repaired pages
- [ ] Identify deallocated pages

## 14.4 Automatic page repair

- [ ] Collect AG automatic page repair history
- [ ] Collect database
- [ ] Collect file and page ID
- [ ] Collect repair status
- [ ] Collect modification time
- [ ] Identify repeated page repair
- [ ] Correlate with suspect pages
- [ ] Correlate with storage errors
- [ ] Escalate repeated repair as underlying storage risk

---

# 15. Security and Access

## 15.1 Server principals

- [ ] Collect SQL logins
- [ ] Collect Windows logins
- [ ] Collect Windows groups
- [ ] Collect login status
- [ ] Collect creation date
- [ ] Collect modification date
- [ ] Collect default database
- [ ] Collect default language
- [ ] Collect password policy enforcement
- [ ] Collect password expiration enforcement
- [ ] Collect credential mapping
- [ ] Identify disabled logins
- [ ] Identify dormant logins where evidence exists
- [ ] Identify SQL-authenticated logins
- [ ] Identify personal administrative logins
- [ ] Identify logins with invalid default databases

## 15.2 Server roles and permissions

- [ ] Collect sysadmin members
- [ ] Collect all fixed server role members
- [ ] Collect custom server roles
- [ ] Collect explicit server permissions
- [ ] Identify CONTROL SERVER
- [ ] Identify ALTER ANY LOGIN
- [ ] Identify IMPERSONATE
- [ ] Identify unsafe bulk or external access permissions
- [ ] Identify excessive privilege
- [ ] Identify direct grants outside approved roles
- [ ] Identify disabled logins retaining privileges

## 15.3 Database users and permissions

- [ ] Collect database users
- [ ] Collect authentication type
- [ ] Collect database role membership
- [ ] Collect explicit database permissions
- [ ] Collect object-level permissions
- [ ] Collect schema permissions
- [ ] Collect schema ownership
- [ ] Collect database ownership
- [ ] Identify orphaned users
- [ ] Identify guest access
- [ ] Identify db_owner members
- [ ] Identify direct CONTROL permissions
- [ ] Identify excessive object grants
- [ ] Identify users mapped to disabled logins
- [ ] Identify personal accounts owning schemas

## 15.4 Security-sensitive database settings

- [ ] Collect TRUSTWORTHY
- [ ] Collect DB_CHAINING
- [ ] Collect cross-database ownership chaining
- [ ] Collect containment
- [ ] Collect external access assemblies
- [ ] Collect unsafe assemblies
- [ ] Collect CLR strict security
- [ ] Collect ownership of trustworthy databases
- [ ] Identify risky combinations

## 15.5 SA and privileged accounts

- [ ] Check SA existence
- [ ] Check SA enabled state
- [ ] Check SA renamed state
- [ ] Check builtin administrator logins
- [ ] Check local administrator access to SQL Server
- [ ] Check emergency sysadmin access
- [ ] Check break-glass account controls

## 15.6 Linked servers and credentials

- [ ] Collect linked servers
- [ ] Collect provider
- [ ] Collect data source
- [ ] Collect RPC settings
- [ ] Collect security mappings
- [ ] Identify linked servers using fixed SQL credentials
- [ ] Identify public login mappings
- [ ] Collect credentials
- [ ] Collect proxies using credentials
- [ ] Identify unused credentials
- [ ] Identify credentials owned by personal accounts

---

# 16. Encryption, TLS, and Certificates

## 16.1 SQL Server network encryption

- [ ] Collect Force Encryption status
- [ ] Collect active connection encryption status
- [ ] Collect TLS protocol version
- [ ] Collect SQL Server certificate thumbprint
- [ ] Collect certificate subject
- [ ] Collect certificate issuer
- [ ] Collect certificate valid-from date
- [ ] Collect certificate expiration date
- [ ] Calculate days until expiration
- [ ] Collect certificate Enhanced Key Usage
- [ ] Validate Server Authentication EKU
- [ ] Validate certificate hostname match
- [ ] Validate private key presence
- [ ] Validate SQL Server service account access to private key
- [ ] Identify self-signed fallback usage
- [ ] Identify unencrypted client connections
- [ ] Identify unsupported TLS protocols

## 16.2 TDE

- [ ] Collect database encryption state
- [ ] Collect encryption algorithm
- [ ] Collect key length
- [ ] Collect encryption progress
- [ ] Collect encryptor type
- [ ] Collect certificate name
- [ ] Collect certificate subject
- [ ] Collect certificate creation date
- [ ] Collect certificate expiration date
- [ ] Calculate days until expiration
- [ ] Identify encrypted databases
- [ ] Identify partially encrypted databases
- [ ] Identify suspended encryption scans
- [ ] Identify missing certificate backup evidence where records exist
- [ ] Identify encrypted databases without documented key ownership

## 16.3 Availability Group endpoint security

- [ ] Collect endpoint state
- [ ] Collect endpoint port
- [ ] Collect authentication type
- [ ] Collect encryption mode
- [ ] Collect encryption algorithm
- [ ] Collect CONNECT permissions
- [ ] Identify excessive endpoint access
- [ ] Collect endpoint certificate details where certificate authentication is used
- [ ] Collect endpoint certificate expiration date
- [ ] Identify endpoint certificates approaching expiration

## 16.4 Certificate expiration thresholds

- [ ] Flag certificates expiring in less than 30 days as Critical
- [ ] Flag certificates expiring in 30–90 days as High
- [ ] Flag certificates expiring in 90–180 days as Warning
- [ ] Report expired certificates
- [ ] Report certificates without expiration metadata
- [ ] Separate Windows TLS certificates from SQL Server internal certificates

---

# 17. SQL Agent, Automation, and Alerting

## 17.1 SQL Agent job inventory

- [ ] Collect enabled jobs
- [ ] Collect disabled jobs
- [ ] Collect job owner
- [ ] Collect category
- [ ] Collect schedule
- [ ] Collect schedule enabled state
- [ ] Collect step count
- [ ] Collect subsystem type
- [ ] Collect last run date
- [ ] Collect last run status
- [ ] Collect last run duration
- [ ] Collect next run date
- [ ] Collect retry attempts
- [ ] Collect retry interval
- [ ] Collect output file
- [ ] Identify jobs without schedules
- [ ] Identify enabled jobs never run
- [ ] Identify disabled jobs with active schedules
- [ ] Identify jobs owned by personal accounts
- [ ] Identify jobs owned by disabled logins
- [ ] Identify jobs referencing invalid databases
- [ ] Identify jobs referencing invalid paths

## 17.2 Job history and reliability

- [ ] Collect failures for the last 90 days
- [ ] Collect successes for the last 90 days
- [ ] Calculate failure ratio
- [ ] Identify recurring failures
- [ ] Identify jobs with no successful runs
- [ ] Identify duration regression
- [ ] Identify long-running jobs
- [ ] Identify overlapping jobs
- [ ] Identify schedule conflicts
- [ ] Identify maintenance-window conflicts
- [ ] Identify jobs with insufficient history retention
- [ ] Identify steps that fail but return job success
- [ ] Identify jobs with no notification on failure

## 17.3 Job ownership and execution context

- [ ] Validate job owner
- [ ] Validate proxy use
- [ ] Collect CmdExec steps
- [ ] Collect PowerShell steps
- [ ] Collect SSIS steps
- [ ] Collect external scripts
- [ ] Identify embedded credentials
- [ ] Identify personal-account execution context
- [ ] Identify excessive proxy permissions
- [ ] Identify unsigned PowerShell usage where relevant

## 17.4 SQL Agent operators

- [ ] Collect operators
- [ ] Collect operator enabled state
- [ ] Collect email address
- [ ] Collect pager configuration
- [ ] Collect weekday and weekend notification windows
- [ ] Collect fail-safe operator
- [ ] Validate fail-safe operator
- [ ] Identify disabled operators referenced by jobs or alerts
- [ ] Identify missing operator contact details

## 17.5 SQL Agent alerts

- [ ] Collect alerts by severity
- [ ] Collect alerts by error number
- [ ] Collect enabled state
- [ ] Collect response delay
- [ ] Collect notification recipients
- [ ] Collect job response
- [ ] Check severity 19–25 alerts
- [ ] Check error 823 alert
- [ ] Check error 824 alert
- [ ] Check error 825 alert
- [ ] Check error 9002 alert
- [ ] Check backup failure alerts
- [ ] Check CHECKDB failure alerts
- [ ] Check AG health alerts
- [ ] Check disk-space alerts
- [ ] Check failed-login alerts where required
- [ ] Identify alerts with no operator
- [ ] Identify alerts with disabled notification paths

## 17.6 Database Mail

- [ ] Collect Database Mail enabled status
- [ ] Collect mail profiles
- [ ] Collect SQL Agent mail profile
- [ ] Collect accounts
- [ ] Collect SMTP server configuration
- [ ] Collect failed mail items
- [ ] Collect unsent mail
- [ ] Collect retrying mail
- [ ] Collect mail queue state
- [ ] Identify stale failed messages
- [ ] Identify SQL Agent without mail profile
- [ ] Identify operator notification failures

---

# 18. Windows and Host Health

## 18.1 Windows System event log

Collect at least the previous 90 days.

- [ ] Disk events
- [ ] StorPort events
- [ ] NTFS events
- [ ] volmgr events
- [ ] volsnap events
- [ ] MPIO events
- [ ] iScsiPrt events
- [ ] FailoverClustering events
- [ ] WHEA-Logger events
- [ ] Kernel-Power events
- [ ] MemoryDiagnostics events
- [ ] Service Control Manager events
- [ ] Unexpected shutdown events
- [ ] Storage reset events
- [ ] Path failure events
- [ ] File-system corruption events
- [ ] Hardware error events

## 18.2 Windows Application event log

- [ ] MSSQLSERVER events
- [ ] Named SQL Server instance events
- [ ] SQLSERVERAGENT events
- [ ] SQLWriter events
- [ ] VSS events
- [ ] Application Error events
- [ ] .NET Runtime events affecting SQL tools
- [ ] SQL Server service crashes
- [ ] SQL Server Agent crashes
- [ ] Backup application failures
- [ ] VSS writer failures
- [ ] Login or authentication failures where logged

## 18.3 Windows services and restart history

- [ ] Collect relevant service state
- [ ] Collect service restart history
- [ ] Identify unexpected SQL Server restarts
- [ ] Identify unexpected cluster service restarts
- [ ] Identify repeated service failures
- [ ] Identify pending reboot
- [ ] Identify uptime
- [ ] Correlate restart time with SQL Server error logs

## 18.4 Antivirus exclusions

- [ ] Collect antivirus product
- [ ] Collect exclusion paths
- [ ] Collect exclusion processes
- [ ] Collect exclusion extensions
- [ ] Validate SQL Server data-file paths
- [ ] Validate transaction-log paths
- [ ] Validate TempDB paths
- [ ] Validate backup paths
- [ ] Validate SQL Server error-log paths
- [ ] Validate Extended Events paths
- [ ] Validate full-text catalog paths
- [ ] Validate FILESTREAM paths
- [ ] Validate SQL Server executable processes
- [ ] Identify missing exclusions
- [ ] Identify obsolete exclusions
- [ ] Identify excessively broad exclusions
- [ ] Identify exclusions covering entire system drives

---

# 19. Availability Groups

## 19.1 AG inventory

- [ ] Collect AG name
- [ ] Collect replica server
- [ ] Collect role
- [ ] Collect operational state
- [ ] Collect connected state
- [ ] Collect synchronization health
- [ ] Collect availability mode
- [ ] Collect failover mode
- [ ] Collect seeding mode
- [ ] Collect backup priority
- [ ] Collect session timeout
- [ ] Collect endpoint URL
- [ ] Identify disconnected replicas
- [ ] Identify unhealthy replicas
- [ ] Identify configuration inconsistencies

## 19.2 Database synchronization state

- [ ] Collect database name
- [ ] Collect synchronization state
- [ ] Collect synchronization health
- [ ] Collect database state
- [ ] Collect suspended state
- [ ] Collect suspend reason
- [ ] Collect is-commit-participant
- [ ] Collect last sent time
- [ ] Collect last received time
- [ ] Collect last hardened time
- [ ] Collect last redone time
- [ ] Identify databases not synchronized
- [ ] Identify suspended databases
- [ ] Identify databases missing from replicas

## 19.3 Log send and redo queues

- [ ] Collect log send queue size
- [ ] Collect log send rate
- [ ] Collect redo queue size
- [ ] Collect redo rate
- [ ] Calculate estimated send catch-up time
- [ ] Calculate estimated redo catch-up time
- [ ] Identify growing send queues
- [ ] Identify growing redo queues
- [ ] Identify zero send or redo rates
- [ ] Identify stale replica timestamps
- [ ] Compare queues against RPO expectations
- [ ] Compare redo delay against operational recovery expectations

## 19.4 AG listener

- [ ] Collect listener name
- [ ] Collect listener port
- [ ] Collect listener IP addresses
- [ ] Collect subnet
- [ ] Collect IP state
- [ ] Collect DNS registration
- [ ] Collect RegisterAllProvidersIP
- [ ] Collect HostRecordTTL
- [ ] Validate multi-subnet listener configuration
- [ ] Identify missing listener IPs
- [ ] Identify stale DNS records
- [ ] Confirm application use of MultiSubnetFailover where applicable

## 19.5 AG backup configuration

- [ ] Collect automated backup preference
- [ ] Collect replica backup priority
- [ ] Collect backup job target logic
- [ ] Validate jobs honor backup preference
- [ ] Identify duplicate backups across replicas
- [ ] Identify missing backups after role changes
- [ ] Identify backup jobs tied to server names instead of replica role

## 19.6 AG errors and connectivity

- [ ] Collect AG-related SQL Server errors
- [ ] Collect replica disconnect events
- [ ] Collect endpoint connection failures
- [ ] Collect timeout events
- [ ] Collect lease timeout events
- [ ] Collect role-change events
- [ ] Collect seeding failures
- [ ] Collect synchronization suspend events
- [ ] Correlate with Windows cluster events
- [ ] Correlate with network events
- [ ] Identify recurring cross-site disconnects

## 19.7 Automatic page repair

- [ ] Collect page repair attempts
- [ ] Collect repair status
- [ ] Collect affected database and page
- [ ] Identify repeated repairs
- [ ] Correlate with suspect pages
- [ ] Correlate with storage errors

## 19.8 Read-only routing

- [ ] Collect readable secondary setting
- [ ] Collect read-only routing URLs
- [ ] Collect routing lists
- [ ] Identify invalid routing targets
- [ ] Identify missing routing configuration
- [ ] Check connection-string support where documented

---

# 20. Windows Server Failover Cluster

## 20.1 Cluster overview

- [ ] Collect cluster name
- [ ] Collect cluster functional level
- [ ] Collect cluster group owner
- [ ] Collect cluster resource state
- [ ] Collect core resource state
- [ ] Collect node state
- [ ] Collect cluster service state
- [ ] Identify failed resources
- [ ] Identify offline resources
- [ ] Identify repeated resource restarts

## 20.2 Quorum and witness

- [ ] Collect quorum type
- [ ] Collect witness type
- [ ] Collect witness resource
- [ ] Collect witness state
- [ ] Collect witness owner
- [ ] Collect node vote
- [ ] Collect dynamic weight
- [ ] Collect current vote
- [ ] Collect Dynamic Quorum setting
- [ ] Validate quorum design against node count and site topology
- [ ] Identify unavailable witness
- [ ] Identify witness access failures
- [ ] Identify vote configuration inconsistencies

## 20.3 Cluster nodes and ownership

- [ ] Collect possible owners for AG resources
- [ ] Collect preferred owners
- [ ] Identify new nodes not configured as possible owners
- [ ] Identify invalid ownership constraints
- [ ] Validate DR node ownership
- [ ] Validate primary-site automatic failover ownership
- [ ] Validate DR-site manual failover ownership

## 20.4 Cluster network

- [ ] Collect cluster networks
- [ ] Collect network role
- [ ] Collect network metric
- [ ] Collect network state
- [ ] Collect subnet
- [ ] Identify unavailable cluster networks
- [ ] Identify networks excluded from cluster communication
- [ ] Validate client-access networks
- [ ] Validate cross-site cluster communication paths

## 20.5 Cluster thresholds

- [ ] Collect SameSubnetDelay
- [ ] Collect SameSubnetThreshold
- [ ] Collect CrossSubnetDelay
- [ ] Collect CrossSubnetThreshold
- [ ] Collect lease timeout
- [ ] Collect health-check timeout
- [ ] Collect failure condition level
- [ ] Collect restart thresholds
- [ ] Validate settings against network topology
- [ ] Identify unsupported or overly aggressive values

## 20.6 Cluster logs and validation

- [ ] Collect recent cluster logs
- [ ] Collect critical FailoverClustering events
- [ ] Collect witness failures
- [ ] Collect node isolation events
- [ ] Collect communication failures
- [ ] Collect quorum-loss events
- [ ] Collect resource deadlock events
- [ ] Collect latest cluster validation report
- [ ] Identify failed validation tests
- [ ] Identify warnings affecting production supportability

---

# 21. Network Health for SQL Server and AG

## 21.1 SQL Server connectivity

- [ ] Collect SQL Server listening ports
- [ ] Collect dynamic or static port configuration
- [ ] Collect endpoint ports
- [ ] Collect listener port
- [ ] Validate firewall rules
- [ ] Validate DNS resolution
- [ ] Validate reverse DNS where required
- [ ] Collect connection failures
- [ ] Collect login timeout events
- [ ] Collect transport-level errors
- [ ] Identify packet reset patterns

## 21.2 Cross-site network evidence

- [ ] Collect round-trip latency
- [ ] Collect packet loss
- [ ] Collect jitter
- [ ] Collect bandwidth
- [ ] Collect MTU
- [ ] Validate MTU consistency
- [ ] Validate route stability
- [ ] Identify scheduled network interruptions
- [ ] Correlate disconnects with AG error logs
- [ ] Correlate disconnects with cluster logs
- [ ] Identify network latency affecting synchronous commit
- [ ] Identify network limitations affecting redo and seeding

---

# 22. Maintenance and Operational Governance

## 22.1 Maintenance coverage

- [ ] Identify backup jobs for all databases
- [ ] Identify log backup jobs for all FULL recovery databases
- [ ] Identify integrity-check jobs for all databases
- [ ] Identify index maintenance jobs
- [ ] Identify statistics maintenance jobs
- [ ] Identify cleanup jobs
- [ ] Identify history-purge jobs
- [ ] Identify jobs without schedules
- [ ] Identify databases excluded from maintenance
- [ ] Identify maintenance jobs exceeding the available window

## 22.2 Maintenance effectiveness

- [ ] Compare maintenance results with current index health
- [ ] Compare statistics maintenance with stale-statistics findings
- [ ] Compare backup jobs with backup history
- [ ] Compare CHECKDB jobs with CHECKDB history
- [ ] Compare cleanup jobs with msdb size
- [ ] Identify jobs reporting success without completing all databases
- [ ] Identify jobs that silently skip unavailable databases
- [ ] Identify maintenance conflicts with business workload

## 22.3 Configuration ownership and documentation

- [ ] Identify owner for each operational process
- [ ] Identify owner for each SQL Agent job
- [ ] Identify owner for backups
- [ ] Identify owner for CHECKDB
- [ ] Identify owner for AG and WSFC
- [ ] Identify owner for certificates
- [ ] Identify owner for security reviews
- [ ] Identify undocumented configuration exceptions
- [ ] Identify personal accounts in operational ownership
- [ ] Identify obsolete jobs and scripts
- [ ] Archive and remove unused operational code where approved

---

# 23. Final Assessment and Recommendations

## 23.1 Finding classification

For every finding, record:

- [ ] Finding ID
- [ ] Chapter
- [ ] Task
- [ ] Observed value
- [ ] Expected value or baseline
- [ ] Severity
- [ ] Affected database, server, replica, or volume
- [ ] Business impact
- [ ] Technical impact
- [ ] Evidence source
- [ ] Recommendation
- [ ] Change risk
- [ ] Validation requirement
- [ ] Owner
- [ ] Target date
- [ ] Status

## 23.2 Severity model

- [ ] Critical — immediate outage, corruption, data-loss, or security exposure
- [ ] High — major operational or performance risk
- [ ] Medium — material optimization or control gap
- [ ] Low — minor configuration improvement
- [ ] Informational — inventory or baseline observation

## 23.3 Recommendation rules

- [ ] Recommend only changes supported by collected evidence
- [ ] Separate findings from assumptions
- [ ] Separate health risks from optimization opportunities
- [ ] Do not recommend restore testing within this checklist
- [ ] Do not claim backup usability without restore validation
- [ ] Do not claim actual RTO without recovery or failover testing
- [ ] Do not use fixed PLE thresholds as standalone evidence
- [ ] Do not use fixed VLF-count thresholds as standalone evidence
- [ ] Do not automatically drop unused indexes
- [ ] Do not automatically drop duplicate statistics
- [ ] Do not recommend trace flag 834 as a standard action
- [ ] Do not state that Instant File Initialization accelerates log growth
- [ ] Do not recommend write-cache changes without storage-vendor evidence
- [ ] Do not recommend compatibility-level changes without regression testing
- [ ] Do not recommend RCSI globally without workload analysis
- [ ] Use interval-based metrics where cumulative values may mislead
