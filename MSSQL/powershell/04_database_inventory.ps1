# =============================================================================
# 04_database_inventory.ps1 — Chapter 4: Database Inventory and Configuration
# Checklist sections: 4.1 – 4.5
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
$chapter  = '04_database_inventory'
$sqlDir   = Join-Path $SqlScriptRoot "sql\04_database_inventory"

. (Join-Path $PSScriptRoot 'shared\HC-Helpers.ps1')

$results = [System.Collections.Generic.List[PSCustomObject]]::new()

$sqlSplat = @{ SqlInstance = $SqlInstance }
if ($SqlCredential) { $sqlSplat['SqlCredential'] = $SqlCredential }

# ── 4.1 Database inventory ────────────────────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     $SqlDb `
    -SqlFile      (Join-Path $sqlDir '04_01_database_inventory.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '04_01' `
    -SectionName  'database_inventory' `
    -Chapter      $chapter))

# ── 4.2 Database options ──────────────────────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     $SqlDb `
    -SqlFile      (Join-Path $sqlDir '04_02_database_options.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '04_02' `
    -SectionName  'database_options' `
    -Chapter      $chapter))

# ── 4.3 Query Store configuration ─────────────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     $SqlDb `
    -SqlFile      (Join-Path $sqlDir '04_03_query_store_config.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '04_03' `
    -SectionName  'query_store_config' `
    -Chapter      $chapter))

# ── 4.4 Ownership and collation ───────────────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     $SqlDb `
    -SqlFile      (Join-Path $sqlDir '04_04_ownership_collation.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '04_04' `
    -SectionName  'ownership_collation' `
    -Chapter      $chapter))

# ── 4.5 Table and object size ─────────────────────────────────────────────────
# Note: this section uses a cursor over all online user databases and may take
# longer on instances with many or large databases. QueryTimeout is extended to
# 600 seconds to accommodate.
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     $SqlDb `
    -SqlFile      (Join-Path $sqlDir '04_05_table_object_size.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '04_05' `
    -SectionName  'table_object_size' `
    -Chapter      $chapter `
    -QueryTimeout 600))

return $results
