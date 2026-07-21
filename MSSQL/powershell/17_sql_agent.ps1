# =============================================================================
# 17_sql_agent.ps1 — Chapter 17: SQL Agent, Automation, and Alerting
# Checklist sections: 17.1 – 17.6
# All sections query msdb context.
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
$chapter = '17_sql_agent'
$sqlDir  = Join-Path $SqlScriptRoot 'sql\17_sql_agent'

. (Join-Path $PSScriptRoot 'shared\HC-Helpers.ps1')

Ensure-HCSqlModule

$results = [System.Collections.Generic.List[PSCustomObject]]::new()

# Shared splat for all SQL sections — every section uses msdb context
$sqlSplat = @{ SqlInstance = $SqlInstance; Database = 'msdb' }
if ($SqlCredential) { $sqlSplat['SqlCredential'] = $SqlCredential }

# ── 17.1  Job Inventory ────────────────────────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -SqlFile     (Join-Path $sqlDir '17_01_job_inventory.sql') `
    -OutputPath  $OutputPath `
    -SectionId   '17_01' `
    -SectionName 'job_inventory' `
    -Chapter     $chapter))

# ── 17.2  Job History Analysis ────────────────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -SqlFile     (Join-Path $sqlDir '17_02_job_history.sql') `
    -OutputPath  $OutputPath `
    -SectionId   '17_02' `
    -SectionName 'job_history' `
    -Chapter     $chapter))

# ── 17.3  Job Ownership and Step Security ─────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -SqlFile     (Join-Path $sqlDir '17_03_job_ownership.sql') `
    -OutputPath  $OutputPath `
    -SectionId   '17_03' `
    -SectionName 'job_ownership' `
    -Chapter     $chapter))

# ── 17.4  Operators ───────────────────────────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -SqlFile     (Join-Path $sqlDir '17_04_operators.sql') `
    -OutputPath  $OutputPath `
    -SectionId   '17_04' `
    -SectionName 'operators' `
    -Chapter     $chapter))

# ── 17.5  Alerts and Coverage ─────────────────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -SqlFile     (Join-Path $sqlDir '17_05_alerts.sql') `
    -OutputPath  $OutputPath `
    -SectionId   '17_05' `
    -SectionName 'alerts' `
    -Chapter     $chapter))

# ── 17.6  Database Mail ───────────────────────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -SqlFile     (Join-Path $sqlDir '17_06_database_mail.sql') `
    -OutputPath  $OutputPath `
    -SectionId   '17_06' `
    -SectionName 'database_mail' `
    -Chapter     $chapter))

return $results
