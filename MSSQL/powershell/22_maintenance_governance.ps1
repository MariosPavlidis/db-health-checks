# =============================================================================
# 22_maintenance_governance.ps1 — Chapter 22: Maintenance and Operational Governance
# Checklist sections: 22.1 – 22.3
# All sections execute SQL files. Sections 22.1 and 22.2 use the msdb
# database context; 22.3 queries both msdb and master (via cross-db refs
# within the SQL file itself against sys.databases / sys.certificates).
# =============================================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SqlInstance,
    [string]$OutputPath                                    = '.\output',
    [string]$SqlDb                                         = 'master',
    [System.Management.Automation.PSCredential]$SqlCredential,
    [switch]$SkipWindowsChecks,
    [string]$SqlScriptRoot                                 = (Join-Path $PSScriptRoot '..')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$chapter = '22_maintenance_governance'
$sqlDir  = Join-Path $SqlScriptRoot 'sql\22_maintenance_governance'

. (Join-Path $PSScriptRoot 'shared\HC-Helpers.ps1')

Ensure-HCSqlModule

$results  = [System.Collections.Generic.List[PSCustomObject]]::new()
$sqlSplat = @{ SqlInstance = $SqlInstance }
if ($SqlCredential) { $sqlSplat['SqlCredential'] = $SqlCredential }

# ── 22.1 Maintenance job coverage ─────────────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -Database    'msdb' `
    -SqlFile     (Join-Path $sqlDir '22_01_maintenance_coverage.sql') `
    -OutputPath  $OutputPath `
    -SectionId   '22_01' `
    -SectionName 'maintenance_coverage' `
    -Chapter     $chapter))

# ── 22.2 Maintenance effectiveness (history + msdb size) ──────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -Database    'msdb' `
    -SqlFile     (Join-Path $sqlDir '22_02_maintenance_effectiveness.sql') `
    -OutputPath  $OutputPath `
    -SectionId   '22_02' `
    -SectionName 'maintenance_effectiveness' `
    -Chapter     $chapter `
    -QueryTimeout 600))

# ── 22.3 Configuration ownership (jobs, databases, certificates) ───────────────
# The SQL file queries msdb for job ownership and master/sys for database
# ownership and certificates; run in master context for widest access.
$results.Add((Invoke-HCSection @sqlSplat `
    -Database    'master' `
    -SqlFile     (Join-Path $sqlDir '22_03_config_ownership.sql') `
    -OutputPath  $OutputPath `
    -SectionId   '22_03' `
    -SectionName 'config_ownership' `
    -Chapter     $chapter))

return $results
