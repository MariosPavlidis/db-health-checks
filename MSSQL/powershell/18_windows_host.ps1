# =============================================================================
# 18_windows_host.ps1 — Chapter 18: Windows and Host Health
# Checklist sections: 18.1 – 18.4
# All sections are PS-native (no SQL queries). All sections are wrapped in
# if (-not $SkipWindowsChecks); when skipped, a SKIP log entry is written
# for each section and $results is returned empty.
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
$chapter = '18_windows_host'

. (Join-Path $PSScriptRoot 'shared\HC-Helpers.ps1')

$results = [System.Collections.Generic.List[PSCustomObject]]::new()

# Resolve computer name once — used by all sections
$computerName = ($SqlInstance -split '\\')[0]
if ($computerName -in @('.', '(local)', 'localhost')) { $computerName = $env:COMPUTERNAME }

# ── 18.1 Windows System Event Log (last 90 days) ──────────────────────────────
if (-not $SkipWindowsChecks) {
    try {
        $startTime = (Get-Date).AddDays(-90)

        $systemSources = @(
            'disk', 'storport', 'ntfs', 'volmgr', 'volsnap', 'mpio', 'iScsiPrt',
            'FailoverClustering', 'WHEA-Logger', 'Microsoft-Windows-Kernel-Power',
            'Microsoft-Windows-MemoryDiagnostics-Results',
            'Service Control Manager', 'EventLog'
        )

        $sysEvents = Get-WinEvent -ComputerName $computerName -FilterHashtable @{
            LogName   = 'System'
            Level     = @(1, 2, 3)   # Critical, Error, Warning
            StartTime = $startTime
        } -ErrorAction SilentlyContinue |
        Where-Object {
            $systemSources -contains $_.ProviderName -or
            $_.ProviderName -match 'disk|stor|ntfs|vol|mpio|iscsi|cluster|whea|kernel|memory'
        } |
        Select-Object TimeCreated, Id, LevelDisplayName, ProviderName,
            @{N='ComputerName'; E={ $computerName }},
            @{N='Message';      E={ $_.Message -replace '\r\n', ' ' }}

        $results.Add((Invoke-HCNativeSection `
            -Data        $sysEvents `
            -OutputPath  $OutputPath `
            -SectionId   '18_01' `
            -SectionName 'system_event_log' `
            -Chapter     $chapter `
            -SqlInstance $SqlInstance))
    }
    catch {
        Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '18_01' `
            -Status 'ERROR' -Message "System event log check failed: $($_.Exception.Message)"
    }
}
else {
    Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '18_01' `
        -Status 'SKIP' -Message 'Windows checks skipped (-SkipWindowsChecks).'
}

# ── 18.2 Windows Application Event Log (last 90 days) ─────────────────────────
if (-not $SkipWindowsChecks) {
    try {
        $startTime = (Get-Date).AddDays(-90)

        $appEvents = Get-WinEvent -ComputerName $computerName -FilterHashtable @{
            LogName   = 'Application'
            Level     = @(1, 2, 3)
            StartTime = $startTime
        } -ErrorAction SilentlyContinue |
        Where-Object { $_.ProviderName -match 'MSSQL|SQL|VSS|SQLWriter|\.NET Runtime' } |
        Select-Object TimeCreated, Id, LevelDisplayName, ProviderName,
            @{N='ComputerName'; E={ $computerName }},
            @{N='Message';      E={ $_.Message -replace '\r\n', ' ' }}

        $results.Add((Invoke-HCNativeSection `
            -Data        $appEvents `
            -OutputPath  $OutputPath `
            -SectionId   '18_02' `
            -SectionName 'application_event_log' `
            -Chapter     $chapter `
            -SqlInstance $SqlInstance))
    }
    catch {
        Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '18_02' `
            -Status 'ERROR' -Message "Application event log check failed: $($_.Exception.Message)"
    }
}
else {
    Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '18_02' `
        -Status 'SKIP' -Message 'Windows checks skipped (-SkipWindowsChecks).'
}

# ── 18.3 Windows services and host uptime ─────────────────────────────────────
if (-not $SkipWindowsChecks) {
    try {
        $services = Get-CimInstance -ClassName Win32_Service -ComputerName $computerName `
                        -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match '^(MSSQL|SQLAgent|SQLBrowser|SQLWriter|ClusSvc)' } |
                    Select-Object @{N='ComputerName'; E={ $computerName }},
                        Name, DisplayName, State, StartMode, StartName

        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $computerName `
                  -ErrorAction SilentlyContinue

        $uptimeData = [PSCustomObject]@{
            ComputerName  = $computerName
            LastBootTime  = if ($os) { $os.LastBootUpTime } else { $null }
            UptimeHours   = if ($os) { [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalHours, 1) } else { $null }
            PendingReboot = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
                            (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
        }

        $combined = @($uptimeData) + @($services)

        $results.Add((Invoke-HCNativeSection `
            -Data        $combined `
            -OutputPath  $OutputPath `
            -SectionId   '18_03' `
            -SectionName 'services_uptime' `
            -Chapter     $chapter `
            -SqlInstance $SqlInstance))
    }
    catch {
        Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '18_03' `
            -Status 'ERROR' -Message "Services/uptime check failed: $($_.Exception.Message)"
    }
}
else {
    Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '18_03' `
        -Status 'SKIP' -Message 'Windows checks skipped (-SkipWindowsChecks).'
}

# ── 18.4 Antivirus exclusions ─────────────────────────────────────────────────
if (-not $SkipWindowsChecks) {
    try {
        try {
            # Prefer Windows Defender API
            $defenderPrefs = Get-MpPreference -ErrorAction Stop
            $avData = [PSCustomObject]@{
                ComputerName        = $computerName
                AVProduct           = 'Windows Defender'
                ExcludedPaths       = ($defenderPrefs.ExclusionPath      -join '; ')
                ExcludedExtensions  = ($defenderPrefs.ExclusionExtension  -join '; ')
                ExcludedProcesses   = ($defenderPrefs.ExclusionProcess    -join '; ')
                RealtimeScanEnabled = ($defenderPrefs.DisableRealtimeMonitoring -eq $false)
            }
        }
        catch {
            # Fallback: enumerate registered AV products via WMI SecurityCenter2
            $avProduct = Get-CimInstance -Namespace 'root\SecurityCenter2' -ClassName AntiVirusProduct `
                             -ComputerName $computerName -ErrorAction SilentlyContinue
            $avData = if ($avProduct) {
                $avProduct | Select-Object `
                    @{N='ComputerName';      E={ $computerName }},
                    displayName,
                    productState,
                    @{N='ExcludedPaths';     E={ 'Could not retrieve - check AV console' }},
                    @{N='Note';              E={
                        'Get-MpPreference failed. Verify exclusions manually for: ' +
                        'data files, log files, tempdb, backup paths, error logs, XE session paths'
                    }}
            } else {
                [PSCustomObject]@{
                    ComputerName       = $computerName
                    AVProduct          = 'Unknown'
                    ExcludedPaths      = 'Could not retrieve'
                    ExcludedExtensions = 'Could not retrieve'
                    ExcludedProcesses  = 'Could not retrieve'
                    Note               = 'Get-MpPreference failed and no AV product found in SecurityCenter2. Verify exclusions manually.'
                }
            }
        }

        $results.Add((Invoke-HCNativeSection `
            -Data        $avData `
            -OutputPath  $OutputPath `
            -SectionId   '18_04' `
            -SectionName 'antivirus_exclusions' `
            -Chapter     $chapter `
            -SqlInstance $SqlInstance))
    }
    catch {
        Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '18_04' `
            -Status 'ERROR' -Message "Antivirus exclusions check failed: $($_.Exception.Message)"
    }
}
else {
    Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '18_04' `
        -Status 'SKIP' -Message 'Windows checks skipped (-SkipWindowsChecks).'
}

return $results
