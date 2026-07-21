# =============================================================================
# 01_cpu_numa_memory.ps1 — Chapter 1: Server Hardware, CPU, NUMA, and Memory
# Checklist sections: 1.1 – 1.7
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
$chapter  = '01_cpu_numa_memory'
$sqlDir   = Join-Path $SqlScriptRoot "sql\01_cpu_numa_memory"

. (Join-Path $PSScriptRoot 'shared\HC-Helpers.ps1')

$results  = [System.Collections.Generic.List[PSCustomObject]]::new()
$sqlSplat = @{ SqlInstance = $SqlInstance }
if ($SqlCredential) { $sqlSplat['SqlCredential'] = $SqlCredential }

# ── 1.1 CPU and NUMA topology ─────────────────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -Database    $SqlDb `
    -SqlFile     (Join-Path $sqlDir '01_01_cpu_numa_topology.sql') `
    -OutputPath  $OutputPath `
    -SectionId   '01_01' `
    -SectionName 'cpu_numa_topology' `
    -Chapter     $chapter))

# ── 1.2 Scheduler health ──────────────────────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -Database    $SqlDb `
    -SqlFile     (Join-Path $sqlDir '01_02_scheduler_health.sql') `
    -OutputPath  $OutputPath `
    -SectionId   '01_02' `
    -SectionName 'scheduler_health' `
    -Chapter     $chapter))

# ── 1.3 Parallelism configuration ────────────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -Database    $SqlDb `
    -SqlFile     (Join-Path $sqlDir '01_03_parallelism_config.sql') `
    -OutputPath  $OutputPath `
    -SectionId   '01_03' `
    -SectionName 'parallelism_config' `
    -Chapter     $chapter))

# ── 1.4 SQL Server memory configuration ──────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -Database    $SqlDb `
    -SqlFile     (Join-Path $sqlDir '01_04_sql_memory_config.sql') `
    -OutputPath  $OutputPath `
    -SectionId   '01_04' `
    -SectionName 'sql_memory_config' `
    -Chapter     $chapter))

# ── 1.5 OS memory and paging (PS-native via WMI) ─────────────────────────────
if (-not $SkipWindowsChecks) {
    try {
        $computerName = ($SqlInstance -split '\\')[0]
        if ($computerName -in @('.','(local)','localhost')) { $computerName = $env:COMPUTERNAME }
        $cimArgs = if ($computerName -ne $env:COMPUTERNAME) { @{ ComputerName = $computerName } } else { @{} }

        $os  = Get-CimInstance -ClassName Win32_OperatingSystem @cimArgs -ErrorAction Stop

        # Page file usage
        $pf = Get-CimInstance -ClassName Win32_PageFileUsage @cimArgs -ErrorAction SilentlyContinue

        $osData = [PSCustomObject]@{
            ComputerName              = $computerName
            TotalPhysicalMemoryMB     = [math]::Round($os.TotalVisibleMemorySize / 1024, 0)
            FreePhysicalMemoryMB      = [math]::Round($os.FreePhysicalMemory / 1024, 0)
            UsedPhysicalMemoryMB      = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1024, 0)
            MemoryUsedPct             = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) * 100.0 / $os.TotalVisibleMemorySize, 1)
            TotalVirtualMemoryMB      = [math]::Round($os.TotalVirtualMemorySize / 1024, 0)
            FreeVirtualMemoryMB       = [math]::Round($os.FreeVirtualMemory / 1024, 0)
            FreeSpaceInPagingFilesMB  = [math]::Round($os.FreeSpaceInPagingFiles / 1024, 0)
            TotalSpaceInPagingFilesMB = [math]::Round($os.SizeStoredInPagingFiles / 1024, 0)
        }

        $pfData = if ($pf) {
            $pf | Select-Object `
                @{N='ComputerName';E={$computerName}},
                Name,
                @{N='AllocatedBaseSizeMB';E={$_.AllocatedBaseSize}},
                @{N='CurrentUsageMB';E={$_.CurrentUsage}},
                @{N='PeakUsageMB';E={$_.PeakUsage}},
                @{N='UsedPct';E={[math]::Round($_.CurrentUsage * 100.0 / [math]::Max($_.AllocatedBaseSize,1), 1)}}
        } else {
            [PSCustomObject]@{ ComputerName = $computerName; Note = 'No page file data returned' }
        }

        $memPressure = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Memory `
            @cimArgs -ErrorAction SilentlyContinue |
            Select-Object `
                @{N='ComputerName';E={$computerName}},
                AvailableMBytes,
                PageFaultsPersec,
                PageReadsPersec,
                PageWritesPersec,
                PagesPersec,
                PoolNonpagedBytes,
                PoolPagedBytes

        $combined = @($osData) + @($pfData)

        $results.Add((Invoke-HCNativeSection `
            -Data        $combined `
            -OutputPath  $OutputPath `
            -SectionId   '01_05' `
            -SectionName 'os_memory_paging' `
            -Chapter     $chapter `
            -SqlInstance $SqlInstance))

        if ($memPressure) {
            $results.Add((Invoke-HCNativeSection `
                -Data        $memPressure `
                -OutputPath  $OutputPath `
                -SectionId   '01_05b' `
                -SectionName 'memory_perf_counters' `
                -Chapter     $chapter `
                -SqlInstance $SqlInstance))
        }
    }
    catch {
        Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '01_05' `
            -Status 'ERROR' -Message "OS memory check failed: $($_.Exception.Message)"
    }
}
else {
    Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '01_05' `
        -Status 'SKIP' -Message 'Windows checks skipped (-SkipWindowsChecks).'
}

# ── 1.6 SQL Server memory internals ──────────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -Database    $SqlDb `
    -SqlFile     (Join-Path $sqlDir '01_06_memory_internals.sql') `
    -OutputPath  $OutputPath `
    -SectionId   '01_06' `
    -SectionName 'memory_internals' `
    -Chapter     $chapter))

# ── 1.7 Power and processor configuration (PS-native via WMI) ────────────────
if (-not $SkipWindowsChecks) {
    try {
        $computerName = ($SqlInstance -split '\\')[0]
        if ($computerName -in @('.','(local)','localhost')) { $computerName = $env:COMPUTERNAME }
        $cimArgs = if ($computerName -ne $env:COMPUTERNAME) { @{ ComputerName = $computerName } } else { @{} }

        # Active power plan
        $powerPlan = Get-CimInstance -Namespace 'root\cimv2\power' `
            -ClassName Win32_PowerPlan @cimArgs -ErrorAction SilentlyContinue |
            Where-Object { $_.IsActive -eq $true }

        $powerData = if ($powerPlan) {
            [PSCustomObject]@{
                ComputerName    = $computerName
                ActivePowerPlan = $powerPlan.ElementName
                PlanGuid        = $powerPlan.InstanceID
                IsHighPerf      = ($powerPlan.ElementName -match 'High performance|Balanced.*SQL' -or
                                   $powerPlan.InstanceID -match '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c')
                Recommendation  = if ($powerPlan.ElementName -notmatch 'High performance') {
                    'WARNING: High Performance power plan is recommended for SQL Server hosts'
                } else { 'OK' }
            }
        } else {
            [PSCustomObject]@{
                ComputerName    = $computerName
                ActivePowerPlan = 'Could not retrieve (check WMI access)'
                IsHighPerf      = $null
                Recommendation  = 'Verify power plan manually'
            }
        }

        # CPU frequency via performance counter
        $cpuFreq = Get-CimInstance -ClassName Win32_Processor @cimArgs -ErrorAction SilentlyContinue |
            Select-Object `
                @{N='ComputerName';E={$computerName}},
                DeviceID,
                Name,
                MaxClockSpeed,
                CurrentClockSpeed,
                @{N='ThrottledPct';E={[math]::Round((1 - $_.CurrentClockSpeed / $_.MaxClockSpeed) * 100, 1)}},
                NumberOfCores,
                NumberOfLogicalProcessors,
                @{N='HotAddEnabled';E={$_.Flags -band 0x1}}

        $results.Add((Invoke-HCNativeSection `
            -Data        ($powerData, $cpuFreq | ForEach-Object { $_ }) `
            -OutputPath  $OutputPath `
            -SectionId   '01_07' `
            -SectionName 'power_processor_config' `
            -Chapter     $chapter `
            -SqlInstance $SqlInstance))
    }
    catch {
        Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '01_07' `
            -Status 'ERROR' -Message "Power/processor check failed: $($_.Exception.Message)"
    }
}
else {
    Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '01_07' `
        -Status 'SKIP' -Message 'Windows checks skipped (-SkipWindowsChecks).'
}

return $results
