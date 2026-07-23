# SQL Server Health Check Toolkit

A PowerShell + T-SQL toolkit that collects diagnostic data from a SQL Server instance and produces self-documenting CSV output — one file per check section. Results are ready to analyse in Excel, Power BI, or any CSV-aware tool.

Covers 22 chapters spanning hardware, configuration, performance, security, backup, integrity, SQL Agent, and high availability.

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
| WinRM / CIM access | Required for Windows-native checks only — use `-SkipWindowsChecks` to bypass |
| `FailoverClusters` PowerShell module | Required for Chapter 20 (WSFC) only — built into Windows Server |

> For Windows-native checks (WMI, event log, cluster), the account running PowerShell must have **local administrator rights** on the SQL Server host.

---

## Quick Start

```powershell
# Install the SqlServer module once
Install-Module SqlServer -Scope CurrentUser -Force

# Run a full health check (Windows Auth)
cd MSSQL\powershell
.\orchestrator.ps1 -SqlInstance "SERVER01"
```

Output is written to `MSSQL\powershell\output\<timestamp>_SERVER01\`.

### Common options

```powershell
# SQL Authentication
$cred = Get-Credential
.\orchestrator.ps1 -SqlInstance "SERVER01" -SqlCredential $cred

# Run specific chapters only
.\orchestrator.ps1 -SqlInstance "SERVER01" -Chapters @("03","13","17")

# Skip Windows-native checks (e.g. running from a remote workstation without WinRM)
.\orchestrator.ps1 -SqlInstance "SERVER01" -SkipWindowsChecks

# Write output to a custom folder
.\orchestrator.ps1 -SqlInstance "SERVER01" -OutputPath "C:\HC_Results"
```

### Re-run a single chapter

Each chapter script accepts the same parameters as the orchestrator:

```powershell
.\13_backup_recovery.ps1 -SqlInstance "SERVER01" -OutputPath "C:\HC_Results\test"
```

### Run a check directly in SSMS or Azure Data Studio

All T-SQL scripts in `MSSQL\sql\` are standalone. Each script sets its own database context, checks the server version, and exits gracefully if the minimum version is not met.

```
Open:        MSSQL\sql\13_backup_recovery\13_01_backup_coverage.sql
Run against: SERVER01 (any database context — script sets its own USE)
```

---

## Output

```
MSSQL\powershell\output\
└── 20260720_143022_SERVER01\
    ├── hc_run.log               ← timestamped log of every section run
    ├── hc_summary.csv           ← one row per chapter: sections run/failed, CSV list
    ├── 01_01_cpu_numa_topology.csv
    ├── 01_02_scheduler_health.csv
    ├── 04_01_database_inventory.csv
    ├── 13_01_backup_coverage.csv
    └── ...
```

Every CSV includes two metadata columns appended at the right:

| Column | Description |
|---|---|
| `CollectedAt` | UTC timestamp of data collection (ISO 8601) |
| `SqlInstance` | Instance name passed to the script |

If a section returned no rows, a single-row CSV is written with `Note = 'No data returned'`.

### Reading the log

```
[2026-07-20T14:30:22Z] [OK]    [13_backup_recovery] [13_01] Exported 42 rows → 13_01_backup_coverage.csv
[2026-07-20T14:30:25Z] [ERROR] [13_backup_recovery] [13_02] ... error message ...
[2026-07-20T14:30:27Z] [SKIP]  [19_availability_groups] [19_01] HADR not enabled on this instance
```

| Status | Meaning |
|---|---|
| `OK` | Section completed and CSV written |
| `WARN` | Section completed with advisory |
| `ERROR` | Section failed — see message for details |
| `SKIP` | Section skipped (feature not enabled, e.g. HADR, Query Store) |
| `INFO` | General orchestration message |

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

### 01 — CPU, NUMA, and Memory

| Check | Script | Description |
|---|---|---|
| 01_01 | `sql/01_cpu_numa_memory/01_01_cpu_numa_topology.sql` | CPU count, socket/core topology, NUMA nodes, soft-NUMA, scheduler distribution |
| 01_02 | `sql/01_cpu_numa_memory/01_02_scheduler_health.sql` | Runnable task count, work queue depth, idle schedulers, worker pressure |
| 01_03 | `sql/01_cpu_numa_memory/01_03_parallelism_config.sql` | MAXDOP and Cost Threshold for Parallelism settings |
| 01_04 | `sql/01_cpu_numa_memory/01_04_sql_memory_config.sql` | Max/min server memory, memory model, lock pages in memory |
| 01_05 | PowerShell (Windows) | OS-level memory, paging file, available RAM |
| 01_06 | `sql/01_cpu_numa_memory/01_06_memory_internals.sql` | Buffer pool, plan cache, memory clerks, stolen memory |

### 02 — Virtualization

| Check | Script | Description |
|---|---|---|
| 02_01 | `sql/02_virtualization/02_01_guest_virtualization.sql` | Hypervisor detection, balloon driver indicators, VM resource limits |

### 03 — Instance Configuration

| Check | Script | Description |
|---|---|---|
| 03_01 | `sql/03_instance_config/03_01_instance_identity.sql` | Instance name, edition, version, collation, authentication mode |
| 03_02 | `sql/03_instance_config/03_02_patch_support.sql` | Build number, patch level, end-of-support status |
| 03_03 | PowerShell (Windows) | Service account, startup type, service SPN |
| 03_04 | `sql/03_instance_config/03_04_instance_config_options.sql` | sp_configure settings — all non-default and key options |
| 03_05 | `sql/03_instance_config/03_05_default_paths_logs.sql` | Default data/log/backup paths, error log path, number of logs retained |

### 04 — Database Inventory

| Check | Script | Description |
|---|---|---|
| 04_01 | `sql/04_database_inventory/04_01_database_inventory.sql` | All databases — state, compatibility level, recovery model, size |
| 04_02 | `sql/04_database_inventory/04_02_database_options.sql` | Auto-close, auto-shrink, page verify, snapshot isolation flags |
| 04_03 | `sql/04_database_inventory/04_03_query_store_config.sql` | Query Store enabled/disabled, size, capture mode per database |
| 04_04 | `sql/04_database_inventory/04_04_ownership_collation.sql` | Database owner, collation mismatch with server default |
| 04_05 | `sql/04_database_inventory/04_05_table_object_size.sql` | Top tables by row count and reserved space per database |

### 05 — Storage, Files, and I/O

| Check | Script | Description |
|---|---|---|
| 05_01 | PowerShell (Windows) | Drive free space and volume configuration |
| 05_02 | `sql/05_storage_files_io/05_02_file_inventory.sql` | Data and log file paths, sizes, growth settings |
| 05_03 | `sql/05_storage_files_io/05_03_autogrowth_shrink.sql` | Files with percent-based autogrowth or auto-shrink enabled |
| 05_04 | PowerShell (Windows) | Disk partition alignment and sector size |
| 05_05 | `sql/05_storage_files_io/05_05_file_io_latency.sql` | Read/write latency per file since last restart (DMV-based) |
| 05_06 | PowerShell (Windows) | Storage controller type, multi-path I/O |
| 05_07 | `sql/05_storage_files_io/05_07_instant_file_init.sql` | Instant file initialization privilege check |

### 06 — TempDB

| Check | Script | Description |
|---|---|---|
| 06_01 | `sql/06_tempdb/06_01_tempdb_config.sql` | File count, equal sizing, placement, trace flag 1117/1118 |
| 06_02 | `sql/06_tempdb/06_02_tempdb_capacity.sql` | Current space used vs allocated, version store size |
| 06_03 | `sql/06_tempdb/06_03_tempdb_performance.sql` | Allocation contention waits, top consumers |

### 07 — Transaction Log

| Check | Script | Description |
|---|---|---|
| 07_01 | `sql/07_transaction_log/07_01_log_config.sql` | Log file size, VLF count, growth configuration per database |
| 07_02 | `sql/07_transaction_log/07_02_vlf_health.sql` | VLF count detail — databases with excessive VLFs flagged |
| 07_03 | `sql/07_transaction_log/07_03_log_reuse.sql` | Log reuse wait reason per database |
| 07_04 | `sql/07_transaction_log/07_04_log_backup_behavior.sql` | Databases in Full/Bulk-Logged with no recent log backup |

### 08 — Performance Baseline

| Check | Script | Description |
|---|---|---|
| 08_01 | `sql/08_performance_baseline/08_01_wait_statistics.sql` | Top wait types since last restart, normalised percentages |
| 08_02 | `sql/08_performance_baseline/08_02_workload_counters.sql` | Batch requests/sec, compilations, re-compilations, PLE |
| 08_03 | `sql/08_performance_baseline/08_03_cpu_worker_analysis.sql` | Active requests, blocking, CPU/memory per session |
| 08_04 | `sql/08_performance_baseline/08_04_memory_plan_cache.sql` | Plan cache size, single-use plans, cache hit ratio |

### 09 — Query Store

| Check | Script | Description |
|---|---|---|
| 09_01 | `sql/09_query_store/09_01_qs_waits.sql` | Top wait categories from Query Store wait stats |
| 09_02 | `sql/09_query_store/09_02_top_resource_queries.sql` | Top queries by CPU, duration, I/O from Query Store |
| 09_03 | `sql/09_query_store/09_03_query_regression.sql` | Queries with plan regressions (increased resource use) |
| 09_04 | `sql/09_query_store/09_04_plan_warnings.sql` | Plans with compile or runtime warnings |

### 10 — Blocking and Locking

| Check | Script | Description |
|---|---|---|
| 10_01 | `sql/10_blocking_locking/10_01_blocking_analysis.sql` | Current blocking chains, head blockers, wait durations |
| 10_02 | `sql/10_blocking_locking/10_02_lock_escalation.sql` | Tables with lock escalation disabled or high escalation counts |
| 10_03 | `sql/10_blocking_locking/10_03_deadlock_history.sql` | Deadlock events from system health XE session |
| 10_04 | `sql/10_blocking_locking/10_04_xe_readiness.sql` | Extended Events session availability and system health status |

### 11 — Index Health

| Check | Script | Description |
|---|---|---|
| 11_01 | `sql/11_index_health/11_01_fragmentation.sql` | Index fragmentation above threshold per database |
| 11_02 | `sql/11_index_health/11_02_missing_indexes.sql` | Missing index recommendations from DMVs, sorted by impact |
| 11_03 | `sql/11_index_health/11_03_unused_indexes.sql` | Indexes with zero or near-zero seeks/scans since last restart |
| 11_04 | `sql/11_index_health/11_04_duplicate_indexes.sql` | Duplicate and redundant index pairs |
| 11_05 | `sql/11_index_health/11_05_index_conditions.sql` | Heaps, disabled indexes, indexes without statistics |
| 11_06 | `sql/11_index_health/11_06_columnstore_health.sql` | Columnstore index row group health and delta store pressure |

### 12 — Statistics

| Check | Script | Description |
|---|---|---|
| 12_01 | `sql/12_statistics/12_01_statistics_inventory.sql` | All user statistics — auto-created vs manual, last updated |
| 12_02 | `sql/12_statistics/12_02_statistics_freshness.sql` | Statistics with high modification counter or not updated in 7+ days |
| 12_03 | `sql/12_statistics/12_03_duplicate_statistics.sql` | Duplicate statistics on the same column(s) |

### 13 — Backup and Recovery

| Check | Script | Description |
|---|---|---|
| 13_01 | `sql/13_backup_recovery/13_01_backup_coverage.sql` | Last full/diff/log backup per database, flag if overdue |
| 13_02 | `sql/13_backup_recovery/13_02_backup_chain.sql` | Backup chain continuity — gaps in log backup history |
| 13_03 | `sql/13_backup_recovery/13_03_rpo_compliance.sql` | RPO assessment — hours since last successful backup by type |
| 13_04 | `sql/13_backup_recovery/13_04_rto_indicators.sql` | Backup size trends, VDI/VSS usage, compressed backup ratio |
| 13_05 | `sql/13_backup_recovery/13_05_backup_retention.sql` | Backup history retention window in msdb |

### 14 — Integrity and Corruption

| Check | Script | Description |
|---|---|---|
| 14_01 | `sql/14_integrity_corruption/14_01_checkdb_history.sql` | Last DBCC CHECKDB run per database, days since last run |
| 14_02 | `sql/14_integrity_corruption/14_02_io_corruption_errors.sql` | 823/824/825 I/O error events from SQL error log |
| 14_03 | `sql/14_integrity_corruption/14_03_suspect_pages.sql` | Entries in msdb.dbo.suspect_pages |
| 14_04 | `sql/14_integrity_corruption/14_04_auto_page_repair.sql` | Auto page repair events (mirrors/AG replicas) |

### 15 — Security and Access

| Check | Script | Description |
|---|---|---|
| 15_01 | `sql/15_security_access/15_01_server_principals.sql` | Server logins — type, status, password policy, last login |
| 15_02 | `sql/15_security_access/15_02_server_roles.sql` | Server role memberships, sysadmin and securityadmin members |
| 15_03 | `sql/15_security_access/15_03_db_users_permissions.sql` | Database users, role memberships, explicit permissions per database |
| 15_04 | `sql/15_security_access/15_04_security_db_settings.sql` | Trustworthy databases, cross-db ownership chaining, guest access |
| 15_05 | `sql/15_security_access/15_05_sa_privileged.sql` | SA account status, renamed SA, accounts with sysadmin |
| 15_06 | `sql/15_security_access/15_06_linked_servers.sql` | Linked server inventory, credentials, RPC/data access settings |

### 16 — Encryption and TLS

| Check | Script | Description |
|---|---|---|
| 16_01 | `sql/16_encryption_tls/16_01_network_encryption.sql` | Force encryption, TLS version in use, certificate binding |
| 16_02 | `sql/16_encryption_tls/16_02_tde.sql` | TDE encryption state per database, key algorithm, thumbprint |
| 16_03 | `sql/16_encryption_tls/16_03_ag_endpoint_security.sql` | AG endpoint encryption algorithm and authentication type |
| 16_04 | `sql/16_encryption_tls/16_04_cert_expiry_summary.sql` | Server certificates and expiry dates |

### 17 — SQL Agent, Automation, and Alerting

| Check | Script | Description |
|---|---|---|
| 17_01 | `sql/17_sql_agent/17_01_job_inventory.sql` | All SQL Agent jobs — schedule, enabled, owner, last run status |
| 17_02 | `sql/17_sql_agent/17_02_job_history.sql` | Job run history — failure rate, silent step failures, recent errors |
| 17_03 | `sql/17_sql_agent/17_03_job_ownership.sql` | Jobs owned by dropped logins or non-SA accounts |
| 17_04 | `sql/17_sql_agent/17_04_operators.sql` | Configured operators and email notification readiness |
| 17_05 | `sql/17_sql_agent/17_05_alerts.sql` | SQL Agent alerts — severity coverage, 823/824/825 alerts |
| 17_06 | `sql/17_sql_agent/17_06_database_mail.sql` | Database Mail profiles, accounts, and send log |

### 18 — Windows Host

| Check | Script | Description |
|---|---|---|
| 18_01–06 | PowerShell (Windows) | OS version/patch level, power plan, .NET version, system event log errors, antivirus exclusions, scheduled tasks |

### 19 — Availability Groups

> Skipped automatically if HADR is not enabled on the instance.

| Check | Script | Description |
|---|---|---|
| 19_01 | `sql/19_availability_groups/19_01_ag_inventory.sql` | AG name, primary replica, failover mode, quorum config |
| 19_02 | `sql/19_availability_groups/19_02_db_sync_state.sql` | Per-database synchronization state and health per replica |
| 19_03 | `sql/19_availability_groups/19_03_send_redo_queues.sql` | Send queue and redo queue size — latency indicators |
| 19_04 | `sql/19_availability_groups/19_04_ag_listener.sql` | AG listeners, IP addresses, port, DNS registration |
| 19_05 | `sql/19_availability_groups/19_05_ag_backup_config.sql` | Backup preference per AG and per database |
| 19_06 | `sql/19_availability_groups/19_06_ag_errors.sql` | AG-related error events from system health XE |
| 19_07 | `sql/19_availability_groups/19_07_auto_page_repair.sql` | Auto page repair attempts across AG replicas |
| 19_08 | `sql/19_availability_groups/19_08_readonly_routing.sql` | Read-only routing configuration and missing routing URLs |

### 20 — Windows Server Failover Clustering

> Skipped automatically if the host is not a cluster node.

| Check | Script | Description |
|---|---|---|
| 20_01–04 | PowerShell (Windows) | Cluster node status, network configuration, quorum settings, cluster event log |

### 21 — Network

| Check | Script | Description |
|---|---|---|
| 21_01–03 | PowerShell (Windows) | NIC configuration, TCP chimney/RSS/offload settings, SQL Server network protocols and ports |

### 22 — Maintenance and Governance

| Check | Script | Description |
|---|---|---|
| 22_01 | `sql/22_maintenance_governance/22_01_maintenance_coverage.sql` | Maintenance solution coverage — index and statistics maintenance jobs |
| 22_02 | `sql/22_maintenance_governance/22_02_maintenance_effectiveness.sql` | Recent maintenance job run history and effectiveness indicators |
| 22_03 | `sql/22_maintenance_governance/22_03_config_ownership.sql` | Configuration drift — sp_configure items changed from recommended defaults |

---

## Operational Utilities

Scripts for use during a health check run. Not part of the collected output — run interactively in a separate SSMS or ADS window.

### Session Monitor and Kill

**`MSSQL/sql/00_session_monitor/00_01_session_monitor.sql`**

Open in a separate window on the same instance while health check scripts are running. Refresh every 10–30 seconds to watch active sessions and kill any that are loading the server.

Targets sessions running the fragmentation scan (`11_01`) and index usage query (`11_03`), which are the most I/O-intensive health check scripts. Includes a ready-to-run `KILL <spid>;` column and a catch-all view of all sessions running longer than 30 seconds.

> **Production note:** `11_01_fragmentation.sql` uses `sys.dm_db_index_physical_stats` in `LIMITED` mode inside a cursor loop across all user databases. On a large instance this can run for several minutes and generate sustained physical reads. Kill immediately if `PhysicalReads` is spiking or `WaitType = PAGEIOLATCH_SH` is sustained.

---

## Permissions Reference

```sql
-- Server level
GRANT VIEW SERVER STATE   TO [health_check_login];
GRANT VIEW ANY DATABASE   TO [health_check_login];

-- msdb (backup history, SQL Agent, suspect pages)
USE msdb;
GRANT SELECT ON SCHEMA::dbo TO [health_check_login];

-- Each user database (index, statistics, Query Store)
-- Option A: add to db_datareader in each database
-- Option B: GRANT VIEW DATABASE STATE at server level (covers DMVs)
```

---

## Version Compatibility

Minimum supported version is **SQL Server 2016**. Scripts that use features introduced in later versions include inline version guards:

```sql
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) >= 15  -- SQL 2019+
BEGIN
    -- 2019-specific query
END
```

On older versions the guarded block is skipped and the CSV will be empty or contain a `Note` row — this is expected, not an error.

---

## Troubleshooting

**`The 'SqlServer' PowerShell module is required`**
Run `Install-Module SqlServer -Scope CurrentUser` then retry.

**`SQL file not found`**
Ensure you are running from the `MSSQL\powershell\` folder, or pass `-SqlScriptRoot` explicitly pointing to the `sql\` directory.

**Sections produce empty CSVs**
Check `hc_run.log` for `SKIP` entries. Common causes: HADR not enabled (Ch 19/20), Query Store not enabled on any database (Ch 09), or instance below the minimum version for that section.

**Windows-native sections fail when run remotely**
Pass `-SkipWindowsChecks` to collect SQL-side data only. WMI/CIM checks require the running account to have local administrator rights on the target host.

**Certificate trust errors**
All `Invoke-Sqlcmd` calls use `-TrustServerCertificate`. If TLS errors persist, verify the SQL Server port is reachable and the instance name is correct.
