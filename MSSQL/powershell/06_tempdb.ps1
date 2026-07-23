# =============================================================================
# 06_tempdb.ps1 — Chapter 6: TempDB
# Checklist sections: 6.1 – 6.7
# =============================================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SqlInstance,
    [string]$OutputPath   = '.\output',
    [string]$SqlDb        = 'master',
    [System.Management.Automation.PSCredential]$SqlCredential,
    [switch]$SkipWindowsChecks,
    [string]$SqlScriptRoot = (Join-Path $PSScriptRoot '..')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$chapter = '06_tempdb'
$sqlDir  = Join-Path $SqlScriptRoot "sql\06_tempdb"

. (Join-Path $PSScriptRoot 'shared\HC-Helpers.ps1')

$results = [System.Collections.Generic.List[PSCustomObject]]::new()

$sqlSplat = @{ SqlInstance = $SqlInstance }
if ($SqlCredential) { $sqlSplat['SqlCredential'] = $SqlCredential }

# ── 6.1 TempDB file configuration ─────────────────────────────────────────────
# Queries sys.master_files (database_id = 2) and sys.dm_db_file_space_usage.
# Flags equal sizing, equal growth settings, and recently added undersized files.
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     $SqlDb `
    -SqlFile      (Join-Path $sqlDir '06_01_tempdb_config.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '06_01' `
    -SectionName  'tempdb_config' `
    -Chapter      $chapter))

# ── 6.2 TempDB capacity and session space usage ────────────────────────────────
# Summary of TempDB space allocation breakdown (user objects, internal objects,
# version store).  Also top 20 sessions by TempDB consumption, and long-running
# transactions causing version store bloat.
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     $SqlDb `
    -SqlFile      (Join-Path $sqlDir '06_02_tempdb_capacity.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '06_02' `
    -SectionName  'tempdb_capacity' `
    -Chapter      $chapter))

# ── 6.3 TempDB performance indicators ─────────────────────────────────────────
# I/O latency per TempDB file, PAGELATCH contention on allocation pages (PFS/GAM/SGAM),
# top queries causing sort/hash spills, and autogrowth events from the default trace.
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     $SqlDb `
    -SqlFile      (Join-Path $sqlDir '06_03_tempdb_performance.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '06_03' `
    -SectionName  'tempdb_performance' `
    -Chapter      $chapter))

# ── 6.4 Row versioning configuration and consumers ────────────────────────────
# Maps RCSI/SNAPSHOT settings and tempdb version-store usage by database, then
# identifies active snapshot transactions and writers that can retain/generate
# row versions.
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     $SqlDb `
    -SqlFile      (Join-Path $sqlDir '06_04_version_store_consumers.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '06_04' `
    -SectionName  'version_store_consumers' `
    -Chapter      $chapter))

# ── 6.5 Active and historical TempDB spills ───────────────────────────────────
# Uses task-level tempdb allocations for active requests and Query Store
# avg/max_tempdb_space_used history on SQL Server 2017+.
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     $SqlDb `
    -SqlFile      (Join-Path $sqlDir '06_05_tempdb_spills.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '06_05' `
    -SectionName  'tempdb_spills' `
    -Chapter      $chapter `
    -QueryTimeout 600))

# ── 6.6 TempDB allocation and metadata contention ─────────────────────────────
# Classifies current tempdb PAGELATCH waits and reports memory-optimized tempdb
# metadata state on SQL Server 2019+.
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     $SqlDb `
    -SqlFile      (Join-Path $sqlDir '06_06_tempdb_metadata_contention.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '06_06' `
    -SectionName  'tempdb_metadata_contention' `
    -Chapter      $chapter))

# ── 6.7 Accelerated Database Recovery persistent version store ────────────────
# Reports ADR configuration, PVS size/cleaner health, and old active
# transactions that can delay cleanup. SQL Server 2016/2017 return a note row.
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     $SqlDb `
    -SqlFile      (Join-Path $sqlDir '06_07_adr_persistent_version_store.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '06_07' `
    -SectionName  'adr_persistent_version_store' `
    -Chapter      $chapter))

return $results
