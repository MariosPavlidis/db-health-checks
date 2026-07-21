# =============================================================================
# 09_query_store.ps1 — Chapter 9: Query Store and Query Performance
# Checklist sections: 9.1 – 9.4
# Notes:
#   - All SQL scripts use internal cursors to iterate over databases with
#     Query Store enabled, so all sections run against master db here.
#   - QueryTimeout is set to 600 seconds to accommodate large instances.
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
$chapter  = '09_query_store'
$sqlDir   = Join-Path $SqlScriptRoot "sql\09_query_store"

. (Join-Path $PSScriptRoot 'shared\HC-Helpers.ps1')

$results  = [System.Collections.Generic.List[PSCustomObject]]::new()
$sqlSplat = @{ SqlInstance = $SqlInstance }
if ($SqlCredential) { $sqlSplat['SqlCredential'] = $SqlCredential }

# ── 9.1 Query Store wait statistics ───────────────────────────────────────────
# Requires SQL 2017+ per database; script handles version guard internally.
$results.Add((Invoke-HCSection @sqlSplat `
    -Database      $SqlDb `
    -SqlFile       (Join-Path $sqlDir '09_01_qs_waits.sql') `
    -OutputPath    $OutputPath `
    -SectionId     '09_01' `
    -SectionName   'qs_waits' `
    -Chapter       $chapter `
    -QueryTimeout  600))

# ── 9.2 Top resource-consuming queries ────────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -Database      $SqlDb `
    -SqlFile       (Join-Path $sqlDir '09_02_top_resource_queries.sql') `
    -OutputPath    $OutputPath `
    -SectionId     '09_02' `
    -SectionName   'top_resource_queries' `
    -Chapter       $chapter `
    -QueryTimeout  600))

# ── 9.3 Query regression and forced plan analysis ─────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -Database      $SqlDb `
    -SqlFile       (Join-Path $sqlDir '09_03_query_regression.sql') `
    -OutputPath    $OutputPath `
    -SectionId     '09_03' `
    -SectionName   'query_regression' `
    -Chapter       $chapter `
    -QueryTimeout  600))

# ── 9.4 Plan warnings detection ───────────────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -Database      $SqlDb `
    -SqlFile       (Join-Path $sqlDir '09_04_plan_warnings.sql') `
    -OutputPath    $OutputPath `
    -SectionId     '09_04' `
    -SectionName   'plan_warnings' `
    -Chapter       $chapter `
    -QueryTimeout  600))

return $results
