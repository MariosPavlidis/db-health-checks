# =============================================================================
# 11_index_health.ps1 — Chapter 11: Index Health
# Checklist sections: 11.1 – 11.6
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
$chapter = '11_index_health'
$sqlDir  = Join-Path $SqlScriptRoot 'sql\11_index_health'

. (Join-Path $PSScriptRoot 'shared\HC-Helpers.ps1')

$results  = [System.Collections.Generic.List[PSCustomObject]]::new()
$sqlSplat = @{ SqlInstance = $SqlInstance }
if ($SqlCredential) { $sqlSplat['SqlCredential'] = $SqlCredential }

# ── 11.01 Index Fragmentation ─────────────────────────────────────────────────
# Uses LIMITED scan mode via sys.dm_db_index_physical_stats; can be slow on
# instances with many large tables. QueryTimeout = 600.
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     $SqlDb `
    -SqlFile      (Join-Path $sqlDir '11_01_fragmentation.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '11_01' `
    -SectionName  'fragmentation' `
    -Chapter      $chapter `
    -QueryTimeout 600))

# ── 11.02 Missing Index Recommendations ───────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     $SqlDb `
    -SqlFile      (Join-Path $sqlDir '11_02_missing_indexes.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '11_02' `
    -SectionName  'missing_indexes' `
    -Chapter      $chapter))

# ── 11.03 Unused Indexes ──────────────────────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     $SqlDb `
    -SqlFile      (Join-Path $sqlDir '11_03_unused_indexes.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '11_03' `
    -SectionName  'unused_indexes' `
    -Chapter      $chapter))

# ── 11.04 Duplicate and Overlapping Indexes ───────────────────────────────────
# STRING_AGG / FOR XML PATH aggregation can be slow on heavily indexed
# databases. QueryTimeout = 600.
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     $SqlDb `
    -SqlFile      (Join-Path $sqlDir '11_04_duplicate_indexes.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '11_04' `
    -SectionName  'duplicate_indexes' `
    -Chapter      $chapter `
    -QueryTimeout 600))

# ── 11.05 Index Conditions ────────────────────────────────────────────────────
# Covers: disabled, hypothetical, heaps, compression/fill factor,
# misaligned, and indexed views.
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     $SqlDb `
    -SqlFile      (Join-Path $sqlDir '11_05_index_conditions.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '11_05' `
    -SectionName  'index_conditions' `
    -Chapter      $chapter))

# ── 11.06 Columnstore Index Health ────────────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     $SqlDb `
    -SqlFile      (Join-Path $sqlDir '11_06_columnstore_health.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '11_06' `
    -SectionName  'columnstore_health' `
    -Chapter      $chapter))

return $results
