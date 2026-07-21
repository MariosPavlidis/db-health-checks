# =============================================================================
# 13_backup_recovery.ps1 — Chapter 13: Backup and Recovery Configuration
# Checklist sections: 13.1 – 13.5
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
$chapter  = '13_backup_recovery'
$sqlDir   = Join-Path $SqlScriptRoot "sql\13_backup_recovery"

. (Join-Path $PSScriptRoot 'shared\HC-Helpers.ps1')

$results = [System.Collections.Generic.List[PSCustomObject]]::new()

$sqlSplat = @{ SqlInstance = $SqlInstance }
if ($SqlCredential) { $sqlSplat['SqlCredential'] = $SqlCredential }

# ── 13.1 Backup coverage ──────────────────────────────────────────────────────
# Runs against msdb to find last full/diff/log per database and flag gaps.
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     'msdb' `
    -SqlFile      (Join-Path $sqlDir '13_01_backup_coverage.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '13_01' `
    -SectionName  'backup_coverage' `
    -Chapter      $chapter))

# ── 13.2 Backup chain integrity ───────────────────────────────────────────────
# Runs against msdb; analyzes LSN chain, recovery model changes, copy-only
# full backups, and differential base inconsistencies over the last 30 days.
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     'msdb' `
    -SqlFile      (Join-Path $sqlDir '13_02_backup_chain.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '13_02' `
    -SectionName  'backup_chain' `
    -Chapter      $chapter))

# ── 13.3 RPO compliance (log backup frequency) ───────────────────────────────
# Runs against msdb; uses LAG() to compute log backup intervals over 90 days
# and flags databases with gaps > 60 min or currently exposed.
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     'msdb' `
    -SqlFile      (Join-Path $sqlDir '13_03_rpo_compliance.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '13_03' `
    -SectionName  'rpo_compliance' `
    -Chapter      $chapter))

# ── 13.4 RTO indicators ───────────────────────────────────────────────────────
# Runs against master (script uses dynamic SQL cursor for VLF counts and
# queries sys.master_files, sys.databases, sys.availability_* from master).
# The script emits multiple result sets; Invoke-HCSection captures the first.
# VLF detail and AG indicators are additional result sets within the same file.
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     'master' `
    -SqlFile      (Join-Path $sqlDir '13_04_rto_indicators.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '13_04' `
    -SectionName  'rto_indicators' `
    -Chapter      $chapter `
    -QueryTimeout 600))

# ── 13.5 Backup retention and cleanup ────────────────────────────────────────
# Runs against msdb; analyzes retention buckets, storage locations, Agent
# jobs with BACKUP commands, failed job history, and throughput statistics.
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     'msdb' `
    -SqlFile      (Join-Path $sqlDir '13_05_backup_retention.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '13_05' `
    -SectionName  'backup_retention' `
    -Chapter      $chapter))

return $results
