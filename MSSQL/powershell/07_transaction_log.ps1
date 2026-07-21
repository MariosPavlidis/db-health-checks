# =============================================================================
# 07_transaction_log.ps1 — Chapter 7: Transaction Log Health
# Checklist sections: 7.1 – 7.4
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
$chapter = '07_transaction_log'
$sqlDir  = Join-Path $SqlScriptRoot "sql\07_transaction_log"

. (Join-Path $PSScriptRoot 'shared\HC-Helpers.ps1')

$results = [System.Collections.Generic.List[PSCustomObject]]::new()

$sqlSplat = @{ SqlInstance = $SqlInstance }
if ($SqlCredential) { $sqlSplat['SqlCredential'] = $SqlCredential }

# ── 7.1 Log file configuration ────────────────────────────────────────────────
# Per-database log file inventory: size, growth, recovery model, log reuse wait.
# VLF counts via sys.dm_db_log_info.  Flags: OversizedLog, UndersizedLog,
# LogSharingStorageWithData, NoRecentLogBackup.
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     $SqlDb `
    -SqlFile      (Join-Path $sqlDir '07_01_log_config.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '07_01' `
    -SectionName  'log_config' `
    -Chapter      $chapter))

# ── 7.2 VLF health ────────────────────────────────────────────────────────────
# Iterates all ONLINE databases with a cursor, collecting VLF count and size
# distribution via sys.dm_db_log_info.  Flags EXCESSIVE_VLF and MANY_SMALL_VLF.
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     $SqlDb `
    -SqlFile      (Join-Path $sqlDir '07_02_vlf_health.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '07_02' `
    -SectionName  'vlf_health' `
    -Chapter      $chapter))

# ── 7.3 Log reuse wait analysis ───────────────────────────────────────────────
# Categorises databases by log_reuse_wait_desc and identifies the root cause:
# LOG_BACKUP, ACTIVE_TRANSACTION, AVAILABILITY_REPLICA, REPLICATION, etc.
# Also lists sessions with open transactions and FULL-recovery databases without
# a recent log backup cross-referenced from msdb.
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     $SqlDb `
    -SqlFile      (Join-Path $sqlDir '07_03_log_reuse.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '07_03' `
    -SectionName  'log_reuse' `
    -Chapter      $chapter))

# ── 7.4 Log backup behavior ───────────────────────────────────────────────────
# Analyses msdb.dbo.backupset log backup history for the last 30 days.
# Uses LAG() to calculate inter-backup gaps.  Flags databases with gaps > 60 min,
# missing 30-day history, and damaged backup records.
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     $SqlDb `
    -SqlFile      (Join-Path $sqlDir '07_04_log_backup_behavior.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '07_04' `
    -SectionName  'log_backup_behavior' `
    -Chapter      $chapter))

return $results
