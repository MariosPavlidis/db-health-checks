# =============================================================================
# 02_virtualization.ps1 — Chapter 2: Virtualization and Hypervisor
# Checklist sections: 2.1 – 2.2
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
$chapter = '02_virtualization'
$sqlDir  = Join-Path $SqlScriptRoot 'sql\02_virtualization'

. (Join-Path $PSScriptRoot 'shared\HC-Helpers.ps1')

Ensure-HCSqlModule

$results  = [System.Collections.Generic.List[PSCustomObject]]::new()
$sqlSplat = @{ SqlInstance = $SqlInstance }
if ($SqlCredential) { $sqlSplat['SqlCredential'] = $SqlCredential }

# ── 2.1 Guest virtualization facts (SQL) ──────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -Database    $SqlDb `
    -SqlFile     (Join-Path $sqlDir '02_01_guest_virtualization.sql') `
    -OutputPath  $OutputPath `
    -SectionId   '02_01' `
    -SectionName 'guest_virtualization' `
    -Chapter     $chapter))

# ── 2.2 Guest VM configuration (PS-native via WMI/CIM) ────────────────────────
if (-not $SkipWindowsChecks) {
    try {
        # Resolve computer name from the instance string
        $computerName = ($SqlInstance -split '\\')[0]
        if ($computerName -in @('.', '(local)', 'localhost')) { $computerName = $env:COMPUTERNAME }

        # VM/hypervisor detection
        $csInfo  = Get-CimInstance -ClassName Win32_ComputerSystem -ComputerName $computerName -ErrorAction SilentlyContinue
        $biosInfo = Get-CimInstance -ClassName Win32_BIOS          -ComputerName $computerName -ErrorAction SilentlyContinue
        $proc    = Get-CimInstance -ClassName Win32_Processor      -ComputerName $computerName -ErrorAction SilentlyContinue

        # Dynamic memory: check Hyper-V integration services presence via WMI
        $hyperVServices = Get-CimInstance -ClassName Win32_Service -ComputerName $computerName `
                              -Filter "Name LIKE 'vmic%'" -ErrorAction SilentlyContinue

        # Snapshot / shadow copy detection
        $shadowCopies = Get-CimInstance -ClassName Win32_ShadowCopy -ComputerName $computerName -ErrorAction SilentlyContinue

        # NTP / time sync status
        $w32tm = & w32tm /query /status 2>&1

        $data = [PSCustomObject]@{
            ComputerName                = $computerName
            Manufacturer                = if ($csInfo)  { $csInfo.Manufacturer }  else { $null }
            Model                       = if ($csInfo)  { $csInfo.Model }          else { $null }
            HypervisorHint              = if ($csInfo -and $csInfo.Model -match 'Virtual|VMware|Hyper-V|KVM|Xen|VirtualBox') {
                                              $csInfo.Model
                                          } elseif ($biosInfo) {
                                              $biosInfo.Description
                                          } else { $null }
            TotalPhysicalMemoryGB       = if ($csInfo)  { [math]::Round($csInfo.TotalPhysicalMemory / 1GB, 1) } else { $null }
            NumberOfProcessors          = if ($csInfo)  { $csInfo.NumberOfProcessors }          else { $null }
            NumberOfLogicalProcs        = if ($csInfo)  { $csInfo.NumberOfLogicalProcessors }   else { $null }
            DynamicMemoryServicePresent = if ($hyperVServices) {
                                              ($hyperVServices | Where-Object { $_.State -eq 'Running' } |
                                               Select-Object -First 1 -ExpandProperty Name)
                                          } else { $null }
            SnapshotCount               = if ($shadowCopies) { @($shadowCopies).Count } else { 0 }
            W32TMStatus                 = ($w32tm -join '; ')
        }

        $results.Add((Invoke-HCNativeSection `
            -Data        $data `
            -OutputPath  $OutputPath `
            -SectionId   '02_02' `
            -SectionName 'guest_vm_config' `
            -Chapter     $chapter `
            -SqlInstance $SqlInstance))
    }
    catch {
        Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '02_02' `
            -Status 'ERROR' -Message "Guest VM config check failed: $($_.Exception.Message)"
    }
}
else {
    Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '02_02' `
        -Status 'SKIP' -Message 'Windows checks skipped (-SkipWindowsChecks).'
}

return $results
