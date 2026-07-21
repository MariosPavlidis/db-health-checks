# =============================================================================
# 19_availability_groups.ps1 — Chapter 19: Availability Groups
# Checklist sections: 19.1 – 19.8
# All sections execute SQL files. HADR is checked first; if not enabled,
# all sections are logged as SKIP and the script returns early.
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
$chapter = '19_availability_groups'
$sqlDir  = Join-Path $SqlScriptRoot 'sql\19_availability_groups'

. (Join-Path $PSScriptRoot 'shared\HC-Helpers.ps1')

Ensure-HCSqlModule

$results  = [System.Collections.Generic.List[PSCustomObject]]::new()
$sqlSplat = @{ SqlInstance = $SqlInstance; Database = 'master' }
if ($SqlCredential) { $sqlSplat['SqlCredential'] = $SqlCredential }

# ── HADR pre-flight check ─────────────────────────────────────────────────────
$hadrSplat = @{ SqlInstance = $SqlInstance }
if ($SqlCredential) { $hadrSplat['SqlCredential'] = $SqlCredential }

$hadrEnabled = Test-HCHadr @hadrSplat

if (-not $hadrEnabled) {
    $sections = @(
        @{ Id = '19_01'; Name = 'ag_inventory' },
        @{ Id = '19_02'; Name = 'db_sync_state' },
        @{ Id = '19_03'; Name = 'send_redo_queues' },
        @{ Id = '19_04'; Name = 'ag_listener' },
        @{ Id = '19_05'; Name = 'ag_backup_config' },
        @{ Id = '19_06'; Name = 'ag_errors' },
        @{ Id = '19_07'; Name = 'auto_page_repair' },
        @{ Id = '19_08'; Name = 'readonly_routing' }
    )
    foreach ($s in $sections) {
        Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section $s.Id `
            -Status 'SKIP' -Message 'HADR not enabled on this instance — section skipped.'
    }
    return $results
}

# ── 19.1 AG inventory and replica state ───────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -SqlFile     (Join-Path $sqlDir '19_01_ag_inventory.sql') `
    -OutputPath  $OutputPath `
    -SectionId   '19_01' `
    -SectionName 'ag_inventory' `
    -Chapter     $chapter))

# ── 19.2 Database synchronization state ───────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -SqlFile     (Join-Path $sqlDir '19_02_db_sync_state.sql') `
    -OutputPath  $OutputPath `
    -SectionId   '19_02' `
    -SectionName 'db_sync_state' `
    -Chapter     $chapter))

# ── 19.3 Send and redo queue depths ───────────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -SqlFile     (Join-Path $sqlDir '19_03_send_redo_queues.sql') `
    -OutputPath  $OutputPath `
    -SectionId   '19_03' `
    -SectionName 'send_redo_queues' `
    -Chapter     $chapter))

# ── 19.4 AG listeners and network configuration ───────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -SqlFile     (Join-Path $sqlDir '19_04_ag_listener.sql') `
    -OutputPath  $OutputPath `
    -SectionId   '19_04' `
    -SectionName 'ag_listener' `
    -Chapter     $chapter))

# ── 19.5 AG backup configuration ──────────────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -SqlFile     (Join-Path $sqlDir '19_05_ag_backup_config.sql') `
    -OutputPath  $OutputPath `
    -SectionId   '19_05' `
    -SectionName 'ag_backup_config' `
    -Chapter     $chapter))

# ── 19.6 AG error log entries ─────────────────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -SqlFile     (Join-Path $sqlDir '19_06_ag_errors.sql') `
    -OutputPath  $OutputPath `
    -SectionId   '19_06' `
    -SectionName 'ag_errors' `
    -Chapter     $chapter `
    -QueryTimeout 600))

# ── 19.7 Automatic page repair ────────────────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -SqlFile     (Join-Path $sqlDir '19_07_auto_page_repair.sql') `
    -OutputPath  $OutputPath `
    -SectionId   '19_07' `
    -SectionName 'auto_page_repair' `
    -Chapter     $chapter))

# ── 19.8 Read-only routing configuration ──────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -SqlFile     (Join-Path $sqlDir '19_08_readonly_routing.sql') `
    -OutputPath  $OutputPath `
    -SectionId   '19_08' `
    -SectionName 'readonly_routing' `
    -Chapter     $chapter))

return $results
