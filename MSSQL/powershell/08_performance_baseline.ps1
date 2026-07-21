# =============================================================================
# 08_performance_baseline.ps1 — Chapter 8: Performance Baseline
# Checklist sections: 8.1 – 8.4
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
$chapter  = '08_performance_baseline'
$sqlDir   = Join-Path $SqlScriptRoot "sql\08_performance_baseline"

. (Join-Path $PSScriptRoot 'shared\HC-Helpers.ps1')

$results  = [System.Collections.Generic.List[PSCustomObject]]::new()
$sqlSplat = @{ SqlInstance = $SqlInstance }
if ($SqlCredential) { $sqlSplat['SqlCredential'] = $SqlCredential }

# ── 8.1 Wait statistics ────────────────────────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -Database    $SqlDb `
    -SqlFile     (Join-Path $sqlDir '08_01_wait_statistics.sql') `
    -OutputPath  $OutputPath `
    -SectionId   '08_01' `
    -SectionName 'wait_statistics' `
    -Chapter     $chapter))

# ── 8.2 Workload performance counters ─────────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -Database    $SqlDb `
    -SqlFile     (Join-Path $sqlDir '08_02_workload_counters.sql') `
    -OutputPath  $OutputPath `
    -SectionId   '08_02' `
    -SectionName 'workload_counters' `
    -Chapter     $chapter))

# ── 8.3 CPU and worker thread analysis ────────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -Database    $SqlDb `
    -SqlFile     (Join-Path $sqlDir '08_03_cpu_worker_analysis.sql') `
    -OutputPath  $OutputPath `
    -SectionId   '08_03' `
    -SectionName 'cpu_worker_analysis' `
    -Chapter     $chapter))

# ── 8.4 Memory and plan cache ─────────────────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -Database    $SqlDb `
    -SqlFile     (Join-Path $sqlDir '08_04_memory_plan_cache.sql') `
    -OutputPath  $OutputPath `
    -SectionId   '08_04' `
    -SectionName 'memory_plan_cache' `
    -Chapter     $chapter))

return $results
