# =============================================================================
# 12_statistics.ps1 — Chapter 12: Statistics Health
# Checklist sections: 12.1 – 12.3
# =============================================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SqlInstance,
    [string]$OutputPath    = '.\output',
    [string]$SqlDb         = 'master',
    [System.Management.Automation.PSCredential]$SqlCredential,
    [switch]$SkipWindowsChecks,
    [string]$SqlScriptRoot = (Join-Path $PSScriptRoot '..')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$chapter = '12_statistics'
$sqlDir  = Join-Path $SqlScriptRoot 'sql\12_statistics'

. (Join-Path $PSScriptRoot 'shared\HC-Helpers.ps1')

$results  = [System.Collections.Generic.List[PSCustomObject]]::new()
$sqlSplat = @{ SqlInstance = $SqlInstance }
if ($SqlCredential) { $sqlSplat['SqlCredential'] = $SqlCredential }

# ── 12.01 Statistics Inventory ────────────────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     $SqlDb `
    -SqlFile      (Join-Path $sqlDir '12_01_statistics_inventory.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '12_01' `
    -SectionName  'statistics_inventory' `
    -Chapter      $chapter `
    -QueryTimeout 600))

# ── 12.02 Statistics Freshness ────────────────────────────────────────────────
# sys.dm_db_stats_properties with CROSS APPLY can be slow on instances with
# very large numbers of statistics objects. QueryTimeout = 600.
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     $SqlDb `
    -SqlFile      (Join-Path $sqlDir '12_02_statistics_freshness.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '12_02' `
    -SectionName  'statistics_freshness' `
    -Chapter      $chapter `
    -QueryTimeout 600))

# ── 12.03 Duplicate and Overlapping Statistics ────────────────────────────────
# Column list aggregation via STRING_AGG or FOR XML PATH can be slow on
# tables with many statistics objects. QueryTimeout = 600.
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     $SqlDb `
    -SqlFile      (Join-Path $sqlDir '12_03_duplicate_statistics.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '12_03' `
    -SectionName  'duplicate_statistics' `
    -Chapter      $chapter `
    -QueryTimeout 600))

return $results
