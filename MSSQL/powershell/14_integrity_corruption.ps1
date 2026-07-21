# =============================================================================
# 14_integrity_corruption.ps1 — Chapter 14: Integrity and Corruption
# Checklist sections: 14.1 – 14.4
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
$chapter  = '14_integrity_corruption'
$sqlDir   = Join-Path $SqlScriptRoot "sql\14_integrity_corruption"

. (Join-Path $PSScriptRoot 'shared\HC-Helpers.ps1')

$results  = [System.Collections.Generic.List[PSCustomObject]]::new()
$sqlSplat = @{ SqlInstance = $SqlInstance }
if ($SqlCredential) { $sqlSplat['SqlCredential'] = $SqlCredential }

# ── 14.1 CHECKDB history ──────────────────────────────────────────────────────
# Reads xp_readerrorlog logs 0-2 for DBCC CHECKDB completion messages and
# joins to sys.databases to identify databases with no evidence of CHECKDB.
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     'msdb' `
    -SqlFile      (Join-Path $sqlDir '14_01_checkdb_history.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '14_01' `
    -SectionName  'checkdb_history' `
    -Chapter      $chapter))

# ── 14.2 I/O corruption errors in error log ───────────────────────────────────
# Searches error logs 0-4 for 823/824/825/832, checksum, torn page, I/O error,
# corrupt, damaged, and bad page messages.
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     'master' `
    -SqlFile      (Join-Path $sqlDir '14_02_io_corruption_errors.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '14_02' `
    -SectionName  'io_corruption_errors' `
    -Chapter      $chapter `
    -QueryTimeout 600))

# ── 14.2b Windows event log — disk and storage errors (PS-native) ─────────────
# Searches the System event log for storage subsystem errors (Disk, volsnap,
# storport) and the Application log for MSSQLSERVER critical/error events.
if (-not $SkipWindowsChecks) {
    try {
        $computerName = ($SqlInstance -split '\\')[0]
        if ($computerName -in @('.', '(local)', 'localhost')) {
            $computerName = $env:COMPUTERNAME
        }

        $cutoff     = (Get-Date).AddDays(-90)
        $eventRows  = [System.Collections.Generic.List[PSCustomObject]]::new()

        # System log: hardware/storage error sources
        $storageSources = @('Disk', 'volsnap', 'storport', 'iaStorAVC', 'stornvme')
        foreach ($src in $storageSources) {
            try {
                $filter = @{
                    LogName      = 'System'
                    ProviderName = $src
                    Level        = @(1, 2)   # Critical = 1, Error = 2
                    StartTime    = $cutoff
                }
                $evts = Get-WinEvent -ComputerName $computerName -FilterHashtable $filter `
                    -ErrorAction SilentlyContinue
                if ($evts) {
                    foreach ($evt in $evts) {
                        $eventRows.Add([PSCustomObject]@{
                            ComputerName = $computerName
                            LogName      = 'System'
                            Source       = $evt.ProviderName
                            EventId      = $evt.Id
                            Level        = $evt.LevelDisplayName
                            TimeCreated  = $evt.TimeCreated
                            Message      = (($evt.Message -replace "`r`n", ' ') -replace "`n", ' ')
                        })
                    }
                }
            }
            catch {
                # Source may not exist on all machines; skip silently
            }
        }

        # Application log: MSSQLSERVER critical/error events
        try {
            $appFilter = @{
                LogName      = 'Application'
                ProviderName = 'MSSQLSERVER'
                Level        = @(1, 2)
                StartTime    = $cutoff
            }
            $appEvts = Get-WinEvent -ComputerName $computerName -FilterHashtable $appFilter `
                -ErrorAction SilentlyContinue
            if ($appEvts) {
                foreach ($evt in $appEvts) {
                    $eventRows.Add([PSCustomObject]@{
                        ComputerName = $computerName
                        LogName      = 'Application'
                        Source       = $evt.ProviderName
                        EventId      = $evt.Id
                        Level        = $evt.LevelDisplayName
                        TimeCreated  = $evt.TimeCreated
                        Message      = (($evt.Message -replace "`r`n", ' ') -replace "`n", ' ')
                    })
                }
            }
        }
        catch {
            # MSSQLSERVER provider may not be present; skip
        }

        $results.Add((Invoke-HCNativeSection `
            -Data        $eventRows `
            -OutputPath  $OutputPath `
            -SectionId   '14_02b' `
            -SectionName 'windows_storage_events' `
            -Chapter     $chapter `
            -SqlInstance $SqlInstance))
    }
    catch {
        Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '14_02b' `
            -Status 'ERROR' -Message "Windows event log check failed: $($_.Exception.Message)"
    }
}
else {
    Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '14_02b' `
        -Status 'SKIP' -Message 'Windows checks skipped (-SkipWindowsChecks).'
}

# ── 14.3 Suspect pages ────────────────────────────────────────────────────────
# Reads msdb.dbo.suspect_pages; flags unresolved, recurring, and recent events.
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     'msdb' `
    -SqlFile      (Join-Path $sqlDir '14_03_suspect_pages.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '14_03' `
    -SectionName  'suspect_pages' `
    -Chapter      $chapter))

# ── 14.4 Auto page repair (HADR) ──────────────────────────────────────────────
# Queries sys.dm_hadr_auto_page_repair.  Returns a note row if HADR is not
# enabled on this instance.
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     'master' `
    -SqlFile      (Join-Path $sqlDir '14_04_auto_page_repair.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '14_04' `
    -SectionName  'auto_page_repair' `
    -Chapter      $chapter))

return $results
