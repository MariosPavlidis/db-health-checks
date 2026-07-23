# SQL Server Health Check

A PowerShell + T-SQL toolkit that collects read-only diagnostic data from a SQL Server instance and exports one self-documenting CSV file per check section. No writes, no maintenance operations, no schema changes.

Covers 22 chapters: hardware, configuration, performance, storage, backup, security, integrity, SQL Agent, Windows host, Availability Groups, WSFC, and maintenance governance.

---

## Repository Structure

```
powershell/         ← orchestrator and per-chapter collection scripts
  orchestrator.ps1
  01_cpu_numa_memory.ps1
  ...
  22_maintenance_governance.ps1
  shared/
    HC-Helpers.ps1  ← dot-sourced by all chapter scripts

sql/                ← standalone T-SQL scripts (run directly in SSMS or ADS)
  01_cpu_numa_memory/
    01_01_cpu_numa_topology.sql
    ...
  ...
  22_maintenance_governance/
```

---

## Requirements

| Requirement | Notes |
|---|---|
| PowerShell 5.1 or 7+ | Built into Windows Server 2016+ |
| SqlServer module | `Install-Module SqlServer -Scope CurrentUser` |
| SQL Server 2016 or later | Minimum supported version |
| `VIEW SERVER STATE` + `VIEW DATABASE STATE` | Required for all DMV-based checks |
| `SELECT` on `msdb..dbo` schema | Required for backup history, SQL Agent, and suspect page checks |
| `db_datareader` on each user database | Required for index, statistics, and Query Store checks |
| WinRM / CIM access | Required for Windows-native checks — use `-SkipWindowsChecks` to bypass |
| `FailoverClusters` RSAT feature | Required for Chapter 20 (WSFC) only |

> For Windows-native checks (WMI, event log, registry, cluster), the account running PowerShell must have **local administrator rights** on the SQL Server host.

---

## Quick Start

```powershell
# Install the SqlServer module once
Install-Module SqlServer -Scope CurrentUser -Force

# Run a full health check (Windows Auth)
cd powershell
.\orchestrator.ps1 -SqlInstance "SERVER01"
```

Output is written to `powershell\output\<timestamp>_SERVER01\`.

### Common options

```powershell
# SQL Authentication
.\orchestrator.ps1 -SqlInstance "SERVER01" -SqlCredential (Get-Credential)

# Run specific chapters only
.\orchestrator.ps1 -SqlInstance "SERVER01" -Chapters @("01","13","19")

# Skip Windows/WMI/registry checks (e.g. running remotely without WinRM)
.\orchestrator.ps1 -SqlInstance "SERVER01" -SkipWindowsChecks

# Write output to a custom folder
.\orchestrator.ps1 -SqlInstance "SERVER01" -OutputPath "D:\hc_output"
```

### Re-run a single chapter

```powershell
.\13_backup_recovery.ps1 -SqlInstance "SERVER01" -OutputPath "D:\hc_output\rerun"
```

### Run a check directly in SSMS or Azure Data Studio

All scripts under `sql\` are standalone. Each sets its own database context, checks the SQL Server version, and exits gracefully if the minimum version is not met.

```
Open:        sql\13_backup_recovery\13_01_backup_coverage.sql
Run against: SERVER01 (any database context — script sets its own USE)
```

---

## Output

```
powershell\output\
└── 20260720_143022_SERVER01\
    ├── hc_run.log          ← timestamped log of every section run
    ├── hc_summary.csv      ← one row per chapter: status, section counts, duration
    ├── 01_01_cpu_numa_topology.csv
    ├── 01_02_scheduler_health.csv
    ├── 13_01_backup_coverage.csv
    └── ...
```

Every CSV includes two metadata columns appended at the right:

| Column | Description |
|---|---|
| `CollectedAt` | UTC timestamp of data collection (ISO 8601) |
| `SqlInstance` | Instance name passed to the script |

If a section returned no rows, a single-row CSV is written with `Note = 'No data returned'`.

### Log status codes

| Status | Meaning |
|---|---|
| `OK` | Section completed and CSV written |
| `WARN` | Section completed with a non-fatal advisory |
| `ERROR` | Section failed — see `hc_run.log` for details |
| `SKIP` | Section not applicable (e.g. HADR not enabled, `-SkipWindowsChecks` set) |
| `PARTIAL` | Chapter completed but one or more sections errored |

### Flag columns

Many scripts include `flag_*` columns (integer 0/1). Filter on `flag_* = 1` to surface items needing attention.

| Flag | Meaning |
|---|---|
| `flag_no_log_backup` | Database in Full/Bulk recovery with no log backup in 24 h |
| `flag_last_run_failed` | SQL Agent job last run failed |
| `flag_high_failure_ratio` | Job failed > 20 % of runs in 90 days |
| `flag_silent_step_failure` | Job step failed but job-level record shows success |
| `flag_no_failure_notification` | Job has no email/page/netsend notification on failure |
| `flag_readable_no_routing_url` | AG readable secondary missing read-only routing URL |

---

## Chapters and Checks

### Utility 00 — Operational Tools

Scripts for use during a health check run, not part of the collected output.

| Section | Output CSV | Source | Description |
|---|---|---|---|
| 00.1 | *(none — run interactively)* | SQL | Session monitor and KILL helper for active health check sessions |

**00.1 — Session Monitor and Kill** (`sql/00_session_monitor/00_01_session_monitor.sql`)

Open in a separate SSMS/ADS window on the same instance while health check scripts are running. Refresh every 10–30 seconds.

The query surfaces all sessions matching the fragmentation and index usage health check scripts (`11_01_fragmentation`, `11_03_unused_indexes`) and any other health check cursor loops. It includes a ready-to-run `KILL <spid>;` column.

> **Production warning:** `11_01_fragmentation.sql` calls `sys.dm_db_index_physical_stats` in `LIMITED` mode inside a cursor loop across all user databases. Even in LIMITED mode this reads allocation pages for every index in every database and can run for several minutes on large instances. Kill if `PhysicalReads` is climbing fast, `WaitType = PAGEIOLATCH_SH` is sustained, or the session is blocking other work.

| Signal | Threshold | Action |
|---|---|---|
| `ElapsedSec` climbing on fragmentation script | > 2 min | Consider killing |
| `PhysicalReads` spiking | Thousands/sec sustained | Kill immediately |
| `WaitType = PAGEIOLATCH_SH` | Sustained | Kill — reading data pages |
| `WaitType = ASYNC_NETWORK_IO` | Any | Safe — results returning |
| `BlockedBy > 0` | Any | Kill the HC session |

---

### Chapter 01 — CPU, NUMA, and Memory

| Section | Output CSV | Source | Description |
|---|---|---|---|
| 1.1 | `01_01_cpu_numa_topology.csv` | SQL | CPU socket/core/NUMA topology, scheduler count and distribution |
| 1.2 | `01_02_scheduler_health.csv` | SQL | Scheduler runqueue depth, worker thread usage |
| 1.3 | `01_03_parallelism_config.csv` | SQL | MAXDOP and Cost Threshold for Parallelism settings |
| 1.4 | `01_04_sql_memory_config.csv` | SQL | Min/max server memory, lock pages in memory, AWE |
| 1.5 | `01_05_os_memory_paging.csv` | WMI | OS total/free/used memory, virtual memory, page file usage |
| 1.5b | `01_05b_memory_perf_counters.csv` | WMI | Available MBytes, page faults/sec, pool bytes |
| 1.6 | `01_06_memory_internals.csv` | SQL | Buffer pool composition, memory clerks breakdown |
| 1.7 | `01_07_power_processor_config.csv` | WMI | Active power plan, CPU clock speed and throttle detection |

### Chapter 02 — Virtualization

| Section | Output CSV | Source | Description |
|---|---|---|---|
| 2.1 | `02_01_guest_virtualization.csv` | SQL | Hypervisor detection, virtual machine flag, host info |
| 2.2 | `02_02_guest_vm_config.csv` | WMI | vCPU count, memory balloon, VM generation |

### Chapter 03 — Instance Configuration

| Section | Output CSV | Source | Description |
|---|---|---|---|
| 3.1 | `03_01_instance_identity.csv` | SQL | Instance name, edition, version, collation, start time |
| 3.2 | `03_02_patch_support.csv` | SQL | Build number, KB, mainstream/extended support end dates |
| 3.2b | `03_02b_pending_reboot.csv` | Registry | Windows pending reboot detection |
| 3.3 | `03_03_sql_services.csv` | WMI | SQL Server services — status, start type, service account |
| 3.3b | `03_03b_service_spns.csv` | setspn.exe | MSSQLSvc SPNs registered for the instance |
| 3.4 | `03_04_instance_config_options.csv` | SQL | All `sp_configure` values with defaults and recommended ranges |
| 3.5 | `03_05_default_paths_logs.csv` | SQL | Default data/log/backup paths, error log location |

### Chapter 04 — Database Inventory

| Section | Output CSV | Source | Description |
|---|---|---|---|
| 4.1 | `04_01_database_inventory.csv` | SQL | All databases — state, recovery model, size, compatibility |
| 4.2 | `04_02_database_options.csv` | SQL | Auto-close, auto-shrink, page verify, snapshot isolation flags |
| 4.3 | `04_03_query_store_config.csv` | SQL | Query Store state, size limits, capture mode per database |
| 4.4 | `04_04_ownership_collation.csv` | SQL | Database owner, collation mismatches vs. instance collation |
| 4.5 | `04_05_table_object_size.csv` | SQL | Top tables by row count and reserved space across all databases |

### Chapter 05 — Storage, Files, and I/O

| Section | Output CSV | Source | Description |
|---|---|---|---|
| 5.1 | `05_01_volume_capacity.csv` | WMI | Drive capacity, free space, free % with OK/WARNING/CRITICAL flag |
| 5.2 | `05_02_file_inventory.csv` | SQL | All database files — path, size, autogrowth, filegroup |
| 5.3 | `05_03_autogrowth_shrink.csv` | SQL | Autogrowth and shrink events from default trace |
| 5.4 | `05_04_disk_sector_size.csv` | WMI + fsutil | NTFS allocation unit size per volume; flags non-64 KB |
| 5.5 | `05_05_file_io_latency.csv` | SQL | Per-file read/write latency from `sys.dm_io_virtual_file_stats` |
| 5.6 | `05_06_storage_subsystem.csv` | WMI | Physical disk media type, health, MPIO detection |
| 5.7 | `05_07_instant_file_init.csv` | SQL | Whether Instant File Initialization is enabled |

### Chapter 06 — TempDB

| Section | Output CSV | Source | Description |
|---|---|---|---|
| 6.1 | `06_01_tempdb_config.csv` | SQL | TempDB file count, sizes, autogrowth, equal-size check |
| 6.2 | `06_02_tempdb_capacity.csv` | SQL | Current space usage — version store, user objects, internal |
| 6.3 | `06_03_tempdb_performance.csv` | SQL | Allocation contention — PFS/GAM/SGAM waits, latch stats |
| 6.4 | `06_04_version_store_consumers.csv` | SQL | RCSI/SNAPSHOT mapping, version-store usage, and active or old snapshot consumers |
| 6.5 | `06_05_tempdb_spills.csv` | SQL | Active internal-object allocations and historical Query Store TempDB usage |
| 6.6 | `06_06_tempdb_metadata_contention.csv` | SQL | PAGELATCH allocation-page classification and memory-optimized TempDB metadata state |
| 6.7 | `06_07_adr_persistent_version_store.csv` | SQL | ADR state, Persistent Version Store health, and transactions delaying cleanup |

### Chapter 07 — Transaction Log

| Section | Output CSV | Source | Description |
|---|---|---|---|
| 7.1 | `07_01_log_config.csv` | SQL | Log file size, used %, autogrowth, recovery model per database |
| 7.2 | `07_02_vlf_health.csv` | SQL | VLF count per database; flags excessive VLF counts |
| 7.3 | `07_03_log_reuse.csv` | SQL | `log_reuse_wait_desc` — what is preventing log truncation |
| 7.4 | `07_04_log_backup_behavior.csv` | SQL | Log backup frequency analysis from `msdb` history |

### Chapter 08 — Performance Baseline

| Section | Output CSV | Source | Description |
|---|---|---|---|
| 8.1 | `08_01_wait_statistics.csv` | SQL | Top wait types since last restart, filtered to actionable waits |
| 8.2 | `08_02_workload_counters.csv` | SQL | Batch requests/sec, compilations, page life expectancy, checkpoints |
| 8.3 | `08_03_cpu_worker_analysis.csv` | SQL | Scheduler load, worker thread saturation, signal waits |
| 8.4 | `08_04_memory_plan_cache.csv` | SQL | Plan cache size, single-use plans, memory pressure indicators |

### Chapter 09 — Query Store

> Skipped automatically for databases where Query Store is not enabled.

| Section | Output CSV | Source | Description |
|---|---|---|---|
| 9.1 | `09_01_qs_waits.csv` | SQL | Top wait categories per database from Query Store |
| 9.2 | `09_02_top_resource_queries.csv` | SQL | Top queries by CPU, duration, I/O from Query Store |
| 9.3 | `09_03_query_regression.csv` | SQL | Queries with plan regressions detected by Query Store |
| 9.4 | `09_04_plan_warnings.csv` | SQL | Queries with implicit conversions, missing stats, or spill warnings |

### Chapter 10 — Blocking and Locking

| Section | Output CSV | Source | Description |
|---|---|---|---|
| 10.1 | `10_01_blocking_analysis.csv` | SQL | Current blocking chains from `sys.dm_exec_requests` |
| 10.2 | `10_02_lock_escalation.csv` | SQL | Lock escalation counts per table, escalation mode settings |
| 10.3 | `10_03_deadlock_history.csv` | SQL | Recent deadlock events from system health XE session |
| 10.4 | `10_04_xe_readiness.csv` | SQL | Extended Events session inventory and system_health status |

### Chapter 11 — Index Health

| Section | Output CSV | Source | Description |
|---|---|---|---|
| 11.1 | `11_01_fragmentation.csv` | SQL | Index fragmentation via `dm_db_index_physical_stats` (LIMITED mode) |
| 11.2 | `11_02_missing_indexes.csv` | SQL | Missing index recommendations from `sys.dm_db_missing_index_details` |
| 11.3 | `11_03_unused_indexes.csv` | SQL | Indexes with zero seeks/scans since last restart |
| 11.4 | `11_04_duplicate_indexes.csv` | SQL | Duplicate and redundant indexes by key column signature |
| 11.5 | `11_05_index_conditions.csv` | SQL | Disabled indexes, indexes without statistics, heap tables |
| 11.6 | `11_06_columnstore_health.csv` | SQL | Columnstore row group health, delta store size, dictionary pressure |

### Chapter 12 — Statistics

| Section | Output CSV | Source | Description |
|---|---|---|---|
| 12.1 | `12_01_statistics_inventory.csv` | SQL | All statistics objects — auto-created, user-created, filtered |
| 12.2 | `12_02_statistics_freshness.csv` | SQL | Statistics last updated, row/modification counts, staleness flag |
| 12.3 | `12_03_duplicate_statistics.csv` | SQL | Overlapping statistics on the same leading column |

### Chapter 13 — Backup and Recovery

| Section | Output CSV | Source | Description |
|---|---|---|---|
| 13.1 | `13_01_backup_coverage.csv` | SQL | Last full/diff/log backup per database; flags missing backups |
| 13.2 | `13_02_backup_chain.csv` | SQL | Log backup chain continuity for FULL recovery model databases |
| 13.3 | `13_03_rpo_compliance.csv` | SQL | RPO gap analysis — time since last backup vs. recovery model |
| 13.4 | `13_04_rto_indicators.csv` | SQL | Backup size trends, compressed ratio, average backup duration |
| 13.5 | `13_05_backup_retention.csv` | SQL | Backup history retention in `msdb`; oldest backup on record |

### Chapter 14 — Integrity and Corruption

| Section | Output CSV | Source | Description |
|---|---|---|---|
| 14.1 | `14_01_checkdb_history.csv` | SQL | CHECKDB completion history from error log; databases with no record |
| 14.2 | `14_02_io_corruption_errors.csv` | SQL | Error log scan for 823/824/825/832, checksum, torn page messages |
| 14.2b | `14_02b_windows_storage_events.csv` | WinEvent | Windows System/Application event log — disk and storage errors |
| 14.3 | `14_03_suspect_pages.csv` | SQL | `msdb.dbo.suspect_pages` — unresolved and recurring entries |
| 14.4 | `14_04_auto_page_repair.csv` | SQL | AG automatic page repair history from `sys.dm_hadr_auto_page_repair` |

### Chapter 15 — Security and Access

| Section | Output CSV | Source | Description |
|---|---|---|---|
| 15.1 | `15_01_server_principals.csv` | SQL | Server logins — type, disabled, password policy, expiration |
| 15.2 | `15_02_server_roles.csv` | SQL | Fixed server role membership, especially sysadmin |
| 15.3 | `15_03_db_users_permissions.csv` | SQL | Database users, role membership, explicit permissions |
| 15.4 | `15_04_security_db_settings.csv` | SQL | Trustworthy bit, guest user, cross-db chaining per database |
| 15.5 | `15_05_sa_privileged.csv` | SQL | SA account status, accounts with CONTROL SERVER, xp_cmdshell state |
| 15.6 | `15_06_linked_servers.csv` | SQL | Linked server inventory — provider, security context, RPC settings |
| 15.7 | `15_07_login_password_policy.csv` | SQL | SQL login password policy, expiration, legacy SHA-1 hash, dormant accounts |
| 15.8 | `15_08_trustworthy_clr_assemblies.csv` | SQL | TRUSTWORTHY sysadmin-owned databases, CLR strict security, UNSAFE/EXTERNAL assemblies |
| 15.9 | `15_09_rls_ddm.csv` | SQL | Row-level security policies and dynamic data masking columns per database |
| 15.10 | `15_10_audit_coverage.csv` | SQL | Server and database audit specifications — enabled audits and action coverage |

### Chapter 16 — Encryption and TLS

| Section | Output CSV | Source | Description |
|---|---|---|---|
| 16.1 | `16_01_network_encryption.csv` | SQL | Connection encryption counts, ForceEncryption, TLS thumbprint |
| 16.1b | `16_01b_windows_tls_certs.csv` | CertStore | Machine store Server Auth certs — expiry, SQL match flag |
| 16.2 | `16_02_tde.csv` | SQL | TDE encryption state per database, certificate name and expiry |
| 16.3 | `16_03_ag_endpoint_security.csv` | SQL | Mirroring endpoint auth type, encryption algorithm, CONNECT grants |
| 16.4 | `16_04_cert_expiry_summary.csv` | SQL | All SQL internal certificates with expiry classification |
| 16.5 | `16_05_endpoint_inventory.csv` | SQL | All endpoint types (T-SQL, Service Broker, mirroring, HADR) — state and CONNECT permissions |
| 16.6 | `16_06_crypto_hierarchy.csv` | SQL | Service master key, database master keys, certificates, asymmetric keys with expiry flags |
| 16.7 | `16_07_always_encrypted.csv` | SQL | Always Encrypted CMK/CEK metadata and encrypted column inventory |
| 16.8 | `16_08_tde_key_availability.csv` | SQL | TDE scan progress for in-flight operations; certificate availability across AG replicas |

### Chapter 17 — SQL Server Agent

| Section | Output CSV | Source | Description |
|---|---|---|---|
| 17.1 | `17_01_job_inventory.csv` | SQL | All Agent jobs — enabled state, schedule, last run status |
| 17.2 | `17_02_job_history.csv` | SQL | Recent job run history — failures, duration trends |
| 17.3 | `17_03_job_ownership.csv` | SQL | Job owners; flags jobs owned by non-SA or disabled logins |
| 17.4 | `17_04_operators.csv` | SQL | Operator inventory and notification configuration |
| 17.5 | `17_05_alerts.csv` | SQL | Alert definitions — severity, error number, notification targets |
| 17.6 | `17_06_database_mail.csv` | SQL | Database Mail profile and account configuration |
| 17.7 | `17_07_credentials_proxies.csv` | SQL | Credentials inventory, proxy-to-subsystem mappings, high-risk subsystem flags |

### Chapter 18 — Windows Host

| Section | Output CSV | Source | Description |
|---|---|---|---|
| 18.1 | `18_01_system_event_log.csv` | WinEvent | System event log errors/criticals from the last 7 days |
| 18.2 | `18_02_application_event_log.csv` | WinEvent | Application event log MSSQLSERVER errors from the last 7 days |
| 18.3 | `18_03_services_uptime.csv` | WMI | OS uptime, last boot time, SQL Server service uptime |
| 18.4 | `18_04_antivirus_exclusions.csv` | Registry | Antivirus product detection and exclusion path check |

### Chapter 19 — Availability Groups

> Skipped automatically when HADR is not enabled on the instance.

| Section | Output CSV | Source | Description |
|---|---|---|---|
| 19.1 | `19_01_ag_inventory.csv` | SQL | AG name, replica state, failover/sync mode; flags sync-commit replicas not healthy |
| 19.2 | `19_02_db_sync_state.csv` | SQL | Per-database synchronization state, suspend reason |
| 19.3 | `19_03_send_redo_queues.csv` | SQL | Send and redo queue sizes with estimated catch-up times |
| 19.4 | `19_04_ag_listener.csv` | SQL | Listener DNS name, IP, port, subnet, DHCP, cluster network config |
| 19.5 | `19_05_ag_backup_config.csv` | SQL | Backup preference per AG and per-replica backup priority |
| 19.6 | `19_06_ag_errors.csv` | SQL | Error log scan for AG lease, seeding, endpoint, and connectivity events |
| 19.7 | `19_07_auto_page_repair.csv` | SQL | Auto page repair attempts across AG replicas |
| 19.8 | `19_08_readonly_routing.csv` | SQL | Read-only routing URLs and routing list configuration |
| 19.9 | `19_09_ag_lease_health.csv` | SQL | Lease and session-timeout health — disconnected or recently errored replicas |
| 19.10 | `19_10_data_loss_failover_readiness.csv` | SQL | Async replica data-loss exposure (redo queue KB); sync replica failover readiness |
| 19.11 | `19_11_log_truncation_holdup.csv` | SQL | Databases where log truncation is blocked by a lagging AG replica |
| 19.12 | `19_12_seeding_health.csv` | SQL | Automatic seeding mode, active seeding progress, seeding failure history |
| 19.13 | `19_13_distributed_ag.csv` | SQL | Distributed Availability Group inventory and member AG health |
| 19.14 | `19_14_contained_ag.csv` | SQL | Contained AG configuration (SQL Server 2022+) |
| 19.15 | `19_15_patch_consistency.csv` | SQL | Local build version and replica server list for patch consistency verification |

### Chapter 20 — Windows Server Failover Clustering

> Requires the `FailoverClusters` RSAT feature. Skipped if not installed or if `-SkipWindowsChecks` is set.

| Section | Output CSV | Source | Description |
|---|---|---|---|
| 20.1 | `20_01_cluster_overview.csv` | WSFC | Cluster summary, all nodes (state, NodeWeight), groups and resources with online/offline flags |
| 20.2 | `20_02_cluster_quorum.csv` | WSFC | Quorum type, quorum resource, per-node vote and dynamic weight |
| 20.3 | `20_03_node_ownership.csv` | WSFC | Possible owner nodes for each SQL Server cluster resource |
| 20.4 | `20_04_cluster_networks.csv` | WSFC | Cluster network adapters — state, role, address, flags for down or unroled networks |
| 20.5 | `20_05_cluster_thresholds.csv` | WSFC | Heartbeat timing parameters: SameSubnetDelay/Threshold, CrossSubnetDelay/Threshold, QuorumArbitrationTimeMax |
| 20.6 | `20_06_cluster_events.csv` | WinEvent | FailoverClustering/Operational event log — Critical/Error/Warning entries from the last 90 days |

### Chapter 21 — Network

| Section | Output CSV | Source | Description |
|---|---|---|---|
| 21.1 | `21_01_connection_errors.csv` | SQL | Connection failure counts from ring buffer and error log |
| 21.1b | `21_01b_listening_port.csv` | SQL | TCP port SQL Server is listening on |
| 21.2 | `21_02_network_connectivity.csv` | PS | DNS resolution and TCP port reachability test |

### Chapter 22 — Maintenance and Governance

| Section | Output CSV | Source | Description |
|---|---|---|---|
| 22.1 | `22_01_maintenance_coverage.csv` | SQL | Databases without a detected maintenance plan or Agent job |
| 22.2 | `22_02_maintenance_effectiveness.csv` | SQL | Index maintenance job history — success rate, last run |
| 22.3 | `22_03_config_ownership.csv` | SQL | Non-default `sp_configure` values, trace flags, change history |

---

## Permissions Reference

### Create the login

```sql
-- Windows Auth (recommended for domain environments)
CREATE LOGIN [DOMAIN\health_check_svc] FROM WINDOWS;

-- SQL Auth (use when Windows Auth is not available)
CREATE LOGIN [health_check_login]
    WITH PASSWORD    = 'ReplaceWithStrongPassword!',
         CHECK_POLICY = ON,
         CHECK_EXPIRATION = ON;
```

### Grant server-level permissions

```sql
-- Required for all DMV-based checks
GRANT VIEW SERVER STATE TO [health_check_login];
GRANT VIEW ANY DATABASE TO [health_check_login];
```

### Grant msdb access

Required for backup history, SQL Agent, and suspect page checks.

```sql
USE msdb;
CREATE USER [health_check_login] FOR LOGIN [health_check_login];
GRANT SELECT ON SCHEMA::dbo TO [health_check_login];
```

### Grant user database access

Required for index, statistics, and Query Store checks.

```sql
-- Run for each user database, or script across all databases:
USE [YourDatabase];
CREATE USER [health_check_login] FOR LOGIN [health_check_login];
ALTER ROLE db_datareader ADD MEMBER [health_check_login];
```

To script across all user databases at once:

```sql
DECLARE @sql NVARCHAR(MAX) = N'';
SELECT @sql += N'
USE ' + QUOTENAME(name) + N';
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N''health_check_login'')
    CREATE USER [health_check_login] FOR LOGIN [health_check_login];
ALTER ROLE db_datareader ADD MEMBER [health_check_login];
'
FROM sys.databases
WHERE state_desc = 'ONLINE'
  AND database_id > 4;   -- exclude system databases

EXEC sys.sp_executesql @sql;
```

> `VIEW SERVER STATE` alone covers most DMV-based checks. `db_datareader` is only needed for index, statistics, and Query Store sections that query catalog tables directly.

---

## Version Compatibility

Minimum supported version is **SQL Server 2016**. Scripts that use features introduced in later versions include inline version guards and exit gracefully on older instances — the CSV will be empty or contain a `Note` row, which is expected.

---

## Troubleshooting

**Scripts are blocked — "file is not digitally signed" or `Write-HCLog` not recognised**
Windows blocks scripts downloaded from the internet. Unblock all scripts before running:
```powershell
Get-ChildItem ".\powershell\" -Recurse -Filter "*.ps1" | Unblock-File
```
Then run the orchestrator **from inside the `powershell\` folder** — `$PSScriptRoot` must resolve correctly for the shared helpers to load:
```powershell
cd MSSQL\powershell
.\orchestrator.ps1 -SqlInstance "SERVER01"
```
If you see `Write-HCLog is not recognised`, the helpers file (`shared\HC-Helpers.ps1`) was not dot-sourced. This is almost always caused by running the script from the wrong working directory or not unblocking all files first.

**`The 'SqlServer' PowerShell module is required`**
Run `Install-Module SqlServer -Scope CurrentUser` then retry.

**Sections produce empty CSVs**
Check `hc_run.log` for `SKIP` entries. Common causes: HADR not enabled (Ch 19/20), Query Store not enabled (Ch 09), or instance below the minimum version for that section.

**Windows-native sections fail when run remotely**
Pass `-SkipWindowsChecks` to collect SQL-side data only. WMI/CIM checks require the running account to have local administrator rights on the target host.

**Certificate trust errors**
All `Invoke-Sqlcmd` calls use `-TrustServerCertificate`. If TLS errors persist, verify the SQL Server port is reachable and the instance name is correct.

---

## Notes

- **Read-only** — no `INSERT`, `UPDATE`, `DELETE`, `DBCC`, `ALTER INDEX`, or `UPDATE STATISTICS` statements are executed.
- **Index fragmentation** (11.1) uses `LIMITED` scan mode — reads allocation pages only, no data page I/O. On large instances with many databases this can still run for several minutes. Use `sql/00_session_monitor/00_01_session_monitor.sql` to watch and kill the session if needed.
- **Windows checks** include all WMI/CIM, event log, registry, certificate store, and `setspn.exe` sections. Pass `-SkipWindowsChecks` when running without WinRM or local admin access on the target.
- **SQL authentication** — pass a `PSCredential` via `-SqlCredential`. If omitted, Windows Integrated Authentication is used.
