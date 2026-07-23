# =============================================================================
# 03_instance_config.ps1 — Chapter 3: SQL Server Instance Configuration
# Checklist sections: 3.1 – 3.5
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
$chapter  = '03_instance_config'
$sqlDir   = Join-Path $SqlScriptRoot "sql\03_instance_config"

. (Join-Path $PSScriptRoot 'shared\HC-Helpers.ps1')

$results = [System.Collections.Generic.List[PSCustomObject]]::new()

$sqlSplat = @{ SqlInstance = $SqlInstance }
if ($SqlCredential) { $sqlSplat['SqlCredential'] = $SqlCredential }

# ── 3.1 Instance identity ─────────────────────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     $SqlDb `
    -SqlFile      (Join-Path $sqlDir '03_01_instance_identity.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '03_01' `
    -SectionName  'instance_identity' `
    -Chapter      $chapter))

# ── 3.2 Patch and support level ───────────────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     $SqlDb `
    -SqlFile      (Join-Path $sqlDir '03_02_patch_support.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '03_02' `
    -SectionName  'patch_support' `
    -Chapter      $chapter))

# ── 3.3 SQL Server services (PS-native) ───────────────────────────────────────
if (-not $SkipWindowsChecks) {
    try {
        # Extract computer name from SQL instance (strip instance name)
        $computerName = ($SqlInstance -split '\\')[0]
        if ($computerName -in @('.', '(local)', 'localhost')) { $computerName = $env:COMPUTERNAME }

        $serviceNames = @('MSSQLSERVER','SQLSERVERAGENT','MSSQLServerOLAPService',
                          'SQLBrowser','SQLTELEMETRY','MSSQLFDLauncher','SQLWriter')

        # Also capture named-instance variants dynamically
        $cimArgs = if ($computerName -ne $env:COMPUTERNAME) { @{ ComputerName = $computerName } } else { @{} }
        $svcList = if ($computerName -ne $env:COMPUTERNAME) {
            Get-Service -ComputerName $computerName -ErrorAction SilentlyContinue
        } else {
            Get-Service -ErrorAction SilentlyContinue
        }
        $svcData = $svcList |
            Where-Object { $_.Name -match '^(MSSQL|SQLSERVER|SQLAgent|SQLBrowser|SQLWriter|MsDtsServer|ReportServer)' } |
            Select-Object @{N='ComputerName';E={$computerName}},
                          @{N='ServiceName';E={$_.Name}},
                          @{N='DisplayName';E={$_.DisplayName}},
                          @{N='Status';E={$_.Status}},
                          @{N='StartType';E={$_.StartType}},
                          @{N='ServiceAccount';E={
                              try { (Get-CimInstance -ClassName Win32_Service @cimArgs -Filter "Name='$($_.Name)'" -ErrorAction SilentlyContinue).StartName }
                              catch { 'N/A' }
                          }}

        $results.Add((Invoke-HCNativeSection `
            -Data        $svcData `
            -OutputPath  $OutputPath `
            -SectionId   '03_03' `
            -SectionName 'sql_services' `
            -Chapter     $chapter `
            -SqlInstance $SqlInstance))

        # SPN check via setspn.exe (best-effort)
        $spnOutput = & setspn -L $computerName 2>&1
        $spnData = $spnOutput | Where-Object { $_ -match 'MSSQLSvc' } |
            ForEach-Object { [PSCustomObject]@{ ComputerName = $computerName; SPN = $_.Trim() } }

        $spnDataOut = if ($spnData) { $spnData } else { @([PSCustomObject]@{ ComputerName = $computerName; SPN = 'No MSSQLSvc SPNs found or setspn.exe not available' }) }
        $results.Add((Invoke-HCNativeSection `
            -Data        $spnDataOut `
            -OutputPath  $OutputPath `
            -SectionId   '03_03b' `
            -SectionName 'service_spns' `
            -Chapter     $chapter `
            -SqlInstance $SqlInstance))

        # Pending reboot check
        $rebootKeys = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
            'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
        )
        $pendingReboot = $false
        if (Test-Path $rebootKeys[0]) { $pendingReboot = $true }
        if (Test-Path $rebootKeys[1]) { $pendingReboot = $true }
        $pfro = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
        if ($pfro) { $pendingReboot = $true }

        $rebootData = [PSCustomObject]@{
            ComputerName   = $computerName
            PendingReboot  = $pendingReboot
        }
        $results.Add((Invoke-HCNativeSection `
            -Data        $rebootData `
            -OutputPath  $OutputPath `
            -SectionId   '03_02b' `
            -SectionName 'pending_reboot' `
            -Chapter     $chapter `
            -SqlInstance $SqlInstance))
    }
    catch {
        Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '03_03' `
            -Status 'ERROR' -Message "Service/SPN check failed: $($_.Exception.Message)"
    }
}
else {
    Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '03_03' `
        -Status 'SKIP' -Message 'Windows checks skipped (-SkipWindowsChecks).'
}

# ── 3.4 Instance configuration options ────────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     $SqlDb `
    -SqlFile      (Join-Path $sqlDir '03_04_instance_config_options.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '03_04' `
    -SectionName  'instance_config_options' `
    -Chapter      $chapter))

# ── 3.5 Default paths and logs ────────────────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     $SqlDb `
    -SqlFile      (Join-Path $sqlDir '03_05_default_paths_logs.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '03_05' `
    -SectionName  'default_paths_logs' `
    -Chapter      $chapter))

# ── 3.6 Non-system objects in master database (SQL) ───────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     'master' `
    -SqlFile      (Join-Path $sqlDir '03_06_master_db_objects.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '03_06' `
    -SectionName  'master_db_objects' `
    -Chapter      $chapter))

return $results
