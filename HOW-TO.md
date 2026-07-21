# SQL Server Health Check — How-To Guide

## Overview

This toolkit collects diagnostic data from a SQL Server instance and produces a set of CSV files — one per health-check section. Each CSV contains the raw data for that section plus two metadata columns (`CollectedAt`, `SqlInstance`) so results are self-documenting and easy to filter in Excel or Power BI.

The tool covers 22 chapters across these areas:

| # | Chapter |
|---|---------|
| 01 | CPU, NUMA, and Memory |
| 02 | Virtualization |
| 03 | Instance Configuration |
| 04 | Database Inventory |
| 05 | Storage, Files, and I/O |
| 06 | TempDB |
| 07 | Transaction Log |
| 08 | Performance Baseline |
| 09 | Query Store |
| 10 | Blocking and Locking |
| 11 | Index Health |
| 12 | Statistics |
| 13 | Backup and Recovery |
| 14 | Integrity and Corruption |
| 15 | Security and Access |
| 16 | Encryption and TLS |
| 17 | SQL Agent, Automation, and Alerting |
| 18 | Windows Host |
| 19 | Availability Groups |
| 20 | Windows Server Failover Clustering |
| 21 | Network |
| 22 | Maintenance and Governance |

---

## Requirements

| Requirement | Notes |
|---|---|
| PowerShell 5.1 or 7+ | Built into Windows Server 2016+ |
| SqlServer module | `Install-Module SqlServer -Scope CurrentUser` |
| SQL Server 2016 or later | Minimum supported version |
| READ access to instance | `VIEW SERVER STATE`, `VIEW DATABASE STATE`, and `msdb` read access |
| Windows Auth or SQL Auth | Windows Auth used by default; pass `-SqlCredential` for SQL Auth |
| WinRM / CIM access | Only required for Windows-native checks (Chapters 01 section 5/7, 02, 03 section 3, 05 sections 1/4/6, 14 section 2, 18, 20, 21). Use `-SkipWindowsChecks` to bypass. |
| FailoverClusters module | Only required for Chapter 20 (WSFC). Built into Windows Server. |

---

## Quick Start

### 1. Install the SqlServer module (once)

```powershell
Install-Module SqlServer -Scope CurrentUser -Force
```

### 2. Run a full health check

```powershell
cd "G:\My Drive\Claude\health_checks\MSSQL\powershell"

.\orchestrator.ps1 -SqlInstance "SERVER01"
```

Output is written to `.\output\<timestamp>_SERVER01\`.

### 3. Run specific chapters only

```powershell
.\orchestrator.ps1 -SqlInstance "SERVER01" -Chapters @("03","13","17")
```

### 4. Use SQL Authentication

```powershell
$cred = Get-Credential
.\orchestrator.ps1 -SqlInstance "SERVER01" -SqlCredential $cred
```

### 5. Skip Windows-native checks (remote execution)

```powershell
.\orchestrator.ps1 -SqlInstance "SERVER01" -SkipWindowsChecks
```

Use this when running from a workstation that does not have WinRM / CIM access to the SQL Server host.

### 6. Custom output folder

```powershell
.\orchestrator.ps1 -SqlInstance "SERVER01" -OutputPath "C:\HC_Results"
```

---

## Output Structure

```
output\
└── 20260720_143022_SERVER01\
    ├── hc_run.log               ← timestamped log of every section run
    ├── hc_summary.csv           ← one row per chapter: sections run/failed, CSV list
    ├── 01_01_cpu_numa_topology.csv
    ├── 01_02_scheduler_health.csv
    ├── 01_05_os_memory_paging.csv
    ├── 04_01_database_inventory.csv
    ├── 13_01_backup_coverage.csv
    └── ...
```

Every CSV has two appended metadata columns:

| Column | Description |
|---|---|
| `CollectedAt` | UTC timestamp of data collection (ISO 8601) |
| `SqlInstance` | Instance name passed to the script |

If a section returned no rows, a single-row CSV is written with `Note = 'No data returned'`.

---

## Running a Single Chapter Script

Each chapter script can be run independently with the same parameters:

```powershell
.\powershell\13_backup_recovery.ps1 `
    -SqlInstance "SERVER01" `
    -OutputPath "C:\HC_Results\test"
```

This is useful for re-running one chapter after fixing an issue without re-running the full suite.

---

## Running Individual SQL Scripts

The T-SQL scripts in `sql\` are standalone and can be run directly in SSMS or Azure Data Studio against the target instance. Each script:

- Checks the SQL Server version at the top and exits gracefully if the minimum version is not met
- Connects to the appropriate database context (`master`, `msdb`, or iterates all user databases)
- Produces a single result set ready to copy/export

Example — run backup coverage check directly in SSMS:

```
Open: sql\13_backup_recovery\13_01_backup_coverage.sql
Run against: SERVER01 (any database context — script sets its own USE)
```

---

## Interpreting Results

### Log file (`hc_run.log`)

Each line follows the format:

```
[2026-07-20T14:30:22Z] [OK]    [13_backup_recovery] [13_01] Exported 42 rows → 13_01_backup_coverage.csv
[2026-07-20T14:30:25Z] [ERROR] [13_backup_recovery] [13_02] ... error message ...
[2026-07-20T14:30:27Z] [SKIP]  [19_availability_groups] [19_01] HADR not enabled on this instance
```

Status codes:

| Status | Meaning |
|---|---|
| `OK` | Section completed and CSV written |
| `WARN` | Section completed with advisory |
| `ERROR` | Section failed; see message for details |
| `SKIP` | Section skipped (feature not enabled, e.g. HADR, Query Store) |
| `INFO` | General orchestration message |

### Flag columns in CSVs

Many SQL scripts include `flag_*` columns (integer 0/1). Filter on `flag_* = 1` to surface items that need attention. Examples:

| Flag | Meaning |
|---|---|
| `flag_no_log_backup` | Database in Full/Bulk recovery with no log backup in 24 h |
| `flag_last_run_failed` | SQL Agent job last run failed |
| `flag_high_failure_ratio` | Job failed > 20% of runs in 90 days |
| `flag_silent_step_failure` | Job step failed but job-level record shows success |
| `flag_no_failure_notification` | Job has no email/page/netsend notification on failure |
| `flag_readable_no_routing_url` | AG readable secondary missing read-only routing URL |

---

## Version Guards

Scripts that use features introduced after SQL Server 2016 RTM include version guards:

```sql
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) >= 15  -- SQL 2019+
BEGIN
    -- 2019-specific query
END
```

On older versions the guarded block is skipped; the CSV will either be empty or contain a `Note` row — this is expected behaviour, not an error.

---

## Permissions Reference

Minimum permissions needed to run all sections:

```sql
-- Server level
GRANT VIEW SERVER STATE TO [health_check_login];
GRANT VIEW ANY DATABASE TO [health_check_login];

-- msdb (for backup history, SQL Agent, suspect pages)
USE msdb;
GRANT SELECT ON SCHEMA::dbo TO [health_check_login];

-- Each user database (for index, statistics, Query Store checks)
-- Easiest: add to db_datareader in each database
-- Or grant VIEW DATABASE STATE at server level (covers DMVs)
```

For Windows-native checks (WMI, event log, cluster), the account running PowerShell must have local administrator rights on the SQL Server host.

---

## Troubleshooting

**`The 'SqlServer' PowerShell module is required`**
Run `Install-Module SqlServer -Scope CurrentUser` then retry.

**`SQL file not found`**
Ensure the script root is the `powershell\` folder or pass `-SqlScriptRoot` explicitly.

**Sections produce empty CSVs**
Check `hc_run.log` for `SKIP` entries. Common reasons: HADR not enabled (Ch 19/20), Query Store not enabled on any database (Ch 09), instance is below the minimum version for that section.

**Windows-native sections fail remotely**
Pass `-SkipWindowsChecks` to collect only SQL-side data. WMI/CIM checks require the running account to have local admin on the target host.

**Certificate trust errors**
All `Invoke-Sqlcmd` calls use `-TrustServerCertificate`. If you still see TLS errors, verify the SQL Server port is reachable and the instance name is correct.
