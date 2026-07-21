# SQL Server Health Check — PowerShell Collection Scripts

Read-only data collection for SQL Server health checks. Runs against a live instance and exports one CSV per section to a timestamped output folder. No writes, no maintenance operations, no schema changes.

---

## Requirements

| Requirement | Notes |
|---|---|
| PowerShell | Windows PowerShell 5.1 or PowerShell 7+ |
| SqlServer module | `Install-Module SqlServer -Scope CurrentUser` |
| SQL permissions | `VIEW SERVER STATE`, `VIEW DATABASE STATE`, read access to `msdb` |
| Windows permissions | Local admin (or WMI/CIM read access) for Windows-native checks |
| WinRM | Only required when targeting a **remote** machine for Windows checks |
| RSAT-Clustering | Only required for chapter 20 (WSFC) |

---

## Usage

```powershell
# Run all chapters against a local instance
.\orchestrator.ps1 -SqlInstance "localhost"

# Run against a named instance with Windows auth
.\orchestrator.ps1 -SqlInstance "SERVER01\INST"

# Run specific chapters only
.\orchestrator.ps1 -SqlInstance "SERVER01" -Chapters @("01","05","11")

# SQL authentication
.\orchestrator.ps1 -SqlInstance "SERVER01" -SqlCredential (Get-Credential)

# Skip Windows/WMI checks (useful when running remotely without WinRM)
.\orchestrator.ps1 -SqlInstance "SERVER01" -SkipWindowsChecks

# Custom output folder
.\orchestrator.ps1 -SqlInstance "SERVER01" -OutputPath "D:\hc_output"
```

---

## Output

Each run creates a timestamped subfolder under `output\`:

```
output\
  20260721_103454_SERVER01\
    hc_run.log              — timestamped log of every section (INFO/OK/WARN/ERROR/SKIP)
    hc_summary.csv          — one row per chapter: status, section counts, duration
    01_01_cpu_numa_topology.csv
    01_02_scheduler_health.csv
    ...
```

The `output\` folder is excluded from source control via `.gitignore`.

---

## Architecture

```
orchestrator.ps1
  └─ shared\HC-Helpers.ps1       (dot-sourced by all scripts)
  └─ 01_cpu_numa_memory.ps1
  └─ 02_virtualization.ps1
  └─ ...
  └─ 22_maintenance_governance.ps1

Each chapter script:
  ├─ SQL sections  → Invoke-HCSection   → reads a .sql file → exports CSV
  └─ PS sections   → Invoke-HCNativeSection → PS-native data → exports CSV
```

All SQL files live under `../sql/{chapter}/` relative to the powershell folder.

---

## Checklist

### Chapter 1 — CPU, NUMA, and Memory

| Section | Output CSV | Source | Description |
|---|---|---|---|
| 1.1 | `01_01_cpu_numa_topology.csv` | SQL | CPU socket/core/NUMA topology, scheduler count |
| 1.2 | `01_02_scheduler_health.csv` | SQL | Scheduler runqueue depth, worker thread usage |
| 1.3 | `01_03_parallelism_config.csv` | SQL | MAXDOP and Cost Threshold for Parallelism settings |
| 1.4 | `01_04_sql_memory_config.csv` | SQL | Min/max server memory, lock pages in memory, AWE |
| 1.5 | `01_05_os_memory_paging.csv` | WMI | OS total/free/used memory, virtual memory, page file usage |
| 1.5b | `01_05b_memory_perf_counters.csv` | WMI | Available MBytes, page faults/sec, pool bytes |
| 1.6 | `01_06_memory_internals.csv` | SQL | Buffer pool composition, memory clerks breakdown |
| 1.7 | `01_07_power_processor_config.csv` | WMI | Active power plan, CPU clock speed and throttle detection |

### Chapter 2 — Virtualization and Hypervisor

| Section | Output CSV | Source | Description |
|---|---|---|---|
| 2.1 | `02_01_guest_virtualization.csv` | SQL | Hypervisor detection, virtual machine flag, host info |
| 2.2 | `02_02_guest_vm_config.csv` | WMI | vCPU count, memory balloon, VM generation |

### Chapter 3 — Instance Configuration

| Section | Output CSV | Source | Description |
|---|---|---|---|
| 3.1 | `03_01_instance_identity.csv` | SQL | Instance name, edition, version, collation, start time |
| 3.2 | `03_02_patch_support.csv` | SQL | Build number, KB, mainstream/extended support end dates |
| 3.2b | `03_02b_pending_reboot.csv` | Registry | Windows pending reboot detection |
| 3.3 | `03_03_sql_services.csv` | WMI | SQL Server services — status, start type, service account |
| 3.3b | `03_03b_service_spns.csv` | setspn.exe | MSSQLSvc SPNs registered for the instance |
| 3.4 | `03_04_instance_config_options.csv` | SQL | All `sp_configure` values with defaults and recommended ranges |
| 3.5 | `03_05_default_paths_logs.csv` | SQL | Default data/log/backup paths, error log location |

### Chapter 4 — Database Inventory

| Section | Output CSV | Source | Description |
|---|---|---|---|
| 4.1 | `04_01_database_inventory.csv` | SQL | All databases — state, recovery model, size, compatibility |
| 4.2 | `04_02_database_options.csv` | SQL | Auto-close, auto-shrink, page verify, snapshot isolation flags |
| 4.3 | `04_03_query_store_config.csv` | SQL | Query Store state, size limits, capture mode per database |
| 4.4 | `04_04_ownership_collation.csv` | SQL | Database owner, collation mismatches vs. instance collation |
| 4.5 | `04_05_table_object_size.csv` | SQL | Top tables by row count and reserved space across all databases |

### Chapter 5 — Storage, Files, and I/O

| Section | Output CSV | Source | Description |
|---|---|---|---|
| 5.1 | `05_01_volume_capacity.csv` | WMI | Drive capacity, free space, free % with OK/WARNING/CRITICAL flag |
| 5.2 | `05_02_file_inventory.csv` | SQL | All database files — path, size, autogrowth, filegroup |
| 5.3 | `05_03_autogrowth_shrink.csv` | SQL | Autogrowth and shrink events from default trace |
| 5.4 | `05_04_disk_sector_size.csv` | WMI + fsutil | NTFS allocation unit size per volume; flags non-64 KB as WARNING |
| 5.5 | `05_05_file_io_latency.csv` | SQL | Per-file read/write latency from `sys.dm_io_virtual_file_stats` |
| 5.6 | `05_06_storage_subsystem.csv` | WMI | Physical disk media type, health, MPIO detection |
| 5.7 | `05_07_instant_file_init.csv` | SQL | Whether Instant File Initialization is enabled |

### Chapter 6 — TempDB

| Section | Output CSV | Source | Description |
|---|---|---|---|
| 6.1 | `06_01_tempdb_config.csv` | SQL | TempDB file count, sizes, autogrowth, equal-size check |
| 6.2 | `06_02_tempdb_capacity.csv` | SQL | TempDB current space usage — version store, user objects, internal |
| 6.3 | `06_03_tempdb_performance.csv` | SQL | TempDB contention — PFS/GAM/SGAM waits, latch stats |

### Chapter 7 — Transaction Log

| Section | Output CSV | Source | Description |
|---|---|---|---|
| 7.1 | `07_01_log_config.csv` | SQL | Log file size, used %, autogrowth, recovery model per database |
| 7.2 | `07_02_vlf_health.csv` | SQL | VLF count per database; flags excessive VLF counts |
| 7.3 | `07_03_log_reuse.csv` | SQL | `log_reuse_wait_desc` — what is preventing log truncation |
| 7.4 | `07_04_log_backup_behavior.csv` | SQL | Log backup frequency analysis from `msdb` history |

### Chapter 8 — Performance Baseline

| Section | Output CSV | Source | Description |
|---|---|---|---|
| 8.1 | `08_01_wait_statistics.csv` | SQL | Top wait types since last restart, filtered to actionable waits |
| 8.2 | `08_02_workload_counters.csv` | SQL | Batch requests/sec, compilations, page life expectancy, checkpoints |
| 8.3 | `08_03_cpu_worker_analysis.csv` | SQL | Scheduler load, worker thread saturation, signal waits |
| 8.4 | `08_04_memory_plan_cache.csv` | SQL | Plan cache size, single-use plans, memory pressure indicators |

### Chapter 9 — Query Store

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
| 13.2 | `13_02_backup_chain.csv` | SQL | Log backup chain continuity check for FULL recovery model databases |
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

### Chapter 16 — Encryption and TLS

| Section | Output CSV | Source | Description |
|---|---|---|---|
| 16.1 | `16_01_network_encryption.csv` | SQL | Connection encryption counts, ForceEncryption, TLS thumbprint |
| 16.1b | `16_01b_windows_tls_certs.csv` | CertStore | Machine store Server Authentication certs — expiry, SQL match flag |
| 16.2 | `16_02_tde.csv` | SQL | TDE encryption state per database, certificate name and expiry |
| 16.3 | `16_03_ag_endpoint_security.csv` | SQL | Mirroring endpoint auth type, encryption algorithm, CONNECT grants |
| 16.4 | `16_04_cert_expiry_summary.csv` | SQL | All SQL internal certificates with expiry classification |

### Chapter 17 — SQL Server Agent

| Section | Output CSV | Source | Description |
|---|---|---|---|
| 17.1 | `17_01_job_inventory.csv` | SQL | All Agent jobs — enabled state, schedule, last run status |
| 17.2 | `17_02_job_history.csv` | SQL | Recent job run history — failures, duration trends |
| 17.3 | `17_03_job_ownership.csv` | SQL | Job owners; flags jobs owned by non-SA or disabled logins |
| 17.4 | `17_04_operators.csv` | SQL | Operator inventory and notification configuration |
| 17.5 | `17_05_alerts.csv` | SQL | Alert definitions — severity, error number, notification targets |
| 17.6 | `17_06_database_mail.csv` | SQL | Database Mail profile and account configuration |

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
| 19.1 | `19_01_ag_inventory.csv` | SQL | AG name, quorum mode, failover mode, health state |
| 19.2 | `19_02_replica_status.csv` | SQL | Replica role, sync state, connected state, failover readiness |
| 19.3 | `19_03_database_sync.csv` | SQL | Per-database sync health, redo/send queue sizes |
| 19.4 | `19_04_listener_config.csv` | SQL | Listener IP, port, network mode |
| 19.5 | `19_05_redo_latency.csv` | SQL | Redo thread latency and estimated recovery time per replica |
| 19.6 | `19_06_log_send_queue.csv` | SQL | Log send queue depth trend per database |
| 19.7 | `19_07_seeding_state.csv` | SQL | Automatic seeding status and progress |
| 19.8 | `19_08_ag_health_events.csv` | SQL | AG state change events from system health XE session |

### Chapter 20 — Windows Server Failover Cluster (WSFC)

> Requires the `FailoverClusters` RSAT feature (`RSAT-Clustering`). Skipped if not installed or if `-SkipWindowsChecks` is set.

| Section | Output CSV | Source | Description |
|---|---|---|---|
| 20.1 | `20_01_cluster_inventory.csv` | WSFC | Cluster name, quorum type, node count, quorum resource |
| 20.2 | `20_02_cluster_nodes.csv` | WSFC | Node state, vote count, dynamic quorum weight |
| 20.3 | `20_03_cluster_networks.csv` | WSFC | Cluster network adapter state and role |
| 20.4 | `20_04_cluster_resources.csv` | WSFC | Resource state per role — online, offline, failed |
| 20.5 | `20_05_quorum_witness.csv` | WSFC | Quorum witness type, share path or disk resource |
| 20.6 | `20_06_cluster_events.csv` | WinEvent | Cluster event log warnings/errors from the last 7 days |

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

## Status Reference

| Status | Meaning |
|---|---|
| `OK` | Section completed, data exported |
| `WARN` | Section completed with a non-fatal warning |
| `ERROR` | Section failed; see `hc_run.log` for details |
| `SKIP` | Section not applicable (e.g. HADR not enabled, `-SkipWindowsChecks` set) |
| `PARTIAL` | Chapter completed but one or more sections errored |

---

## Notes

- **Read-only.** No `INSERT`, `UPDATE`, `DELETE`, `DBCC`, `ALTER INDEX`, or `UPDATE STATISTICS` statements are executed.
- **Index fragmentation** (11.1) uses `LIMITED` scan mode — reads allocation pages only, no data page I/O.
- **Windows checks** (`-SkipWindowsChecks`) include all WMI/CIM, event log, registry, certificate store, and `setspn.exe` sections. Omit this switch when running locally or with WinRM enabled.
- **Remote execution** for Windows checks requires WinRM on the target. CIM/WMI calls are automatically directed to local DCOM when targeting `localhost` or the local machine name.
- **SQL authentication** — pass a `PSCredential` via `-SqlCredential`. If omitted, Windows Integrated Authentication is used.
