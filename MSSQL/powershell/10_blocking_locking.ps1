# =============================================================================
# 10_blocking_locking.ps1 — Chapter 10: Blocking, Locking, and Deadlocks
# Checklist sections: 10.1 – 10.4
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
$chapter  = '10_blocking_locking'
$sqlDir   = Join-Path $SqlScriptRoot "sql\10_blocking_locking"

. (Join-Path $PSScriptRoot 'shared\HC-Helpers.ps1')

$results  = [System.Collections.Generic.List[PSCustomObject]]::new()
$sqlSplat = @{ SqlInstance = $SqlInstance }
if ($SqlCredential) { $sqlSplat['SqlCredential'] = $SqlCredential }

# ── 10.1 Blocking chain analysis ──────────────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -Database    $SqlDb `
    -SqlFile     (Join-Path $sqlDir '10_01_blocking_analysis.sql') `
    -OutputPath  $OutputPath `
    -SectionId   '10_01' `
    -SectionName 'blocking_analysis' `
    -Chapter     $chapter))

# ── 10.2 Lock escalation and current lock snapshot ────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -Database    $SqlDb `
    -SqlFile     (Join-Path $sqlDir '10_02_lock_escalation.sql') `
    -OutputPath  $OutputPath `
    -SectionId   '10_02' `
    -SectionName 'lock_escalation' `
    -Chapter     $chapter))

# ── 10.3 Deadlock history from Extended Events ────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -Database    $SqlDb `
    -SqlFile     (Join-Path $sqlDir '10_03_deadlock_history.sql') `
    -OutputPath  $OutputPath `
    -SectionId   '10_03' `
    -SectionName 'deadlock_history' `
    -Chapter     $chapter))

# ── 10.4 Extended Events session readiness ────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -Database    $SqlDb `
    -SqlFile     (Join-Path $sqlDir '10_04_xe_readiness.sql') `
    -OutputPath  $OutputPath `
    -SectionId   '10_04' `
    -SectionName 'xe_readiness' `
    -Chapter     $chapter))

return $results
