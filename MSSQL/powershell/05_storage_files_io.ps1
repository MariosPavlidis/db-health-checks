# =============================================================================
# 05_storage_files_io.ps1 — Chapter 5: Storage, Volumes, Files, and I/O
# Checklist sections: 5.1 – 5.7
# =============================================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SqlInstance,
    [string]$OutputPath    = '.\output',
    [string]$SqlDb         = 'master',
    [System.Management.Automation.PSCredential]$SqlCredential,
    [switch]$SkipWindowsChecks,
    [string]$SqlScriptRoot = (Join-Path $PSScriptRoot '..')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$chapter = '05_storage_files_io'
$sqlDir  = Join-Path $SqlScriptRoot "sql\05_storage_files_io"

. (Join-Path $PSScriptRoot 'shared\HC-Helpers.ps1')

$results  = [System.Collections.Generic.List[PSCustomObject]]::new()
$sqlSplat = @{ SqlInstance = $SqlInstance }
if ($SqlCredential) { $sqlSplat['SqlCredential'] = $SqlCredential }

# Resolve the computer name from the instance string for WMI/CIM calls.
# Handles "SERVER\INSTANCE", "SERVER,PORT", "." and localhost aliases.
$computerName = ($SqlInstance -split '[\\,]')[0].Trim()
if ($computerName -in @('.', '(local)', 'localhost', '')) {
    $computerName = $env:COMPUTERNAME
}
$cimArgs = if ($computerName -ne $env:COMPUTERNAME) { @{ ComputerName = $computerName } } else { @{} }

# ── 5.1 Volume capacity (PS-native via CIM/WMI) ───────────────────────────────
if (-not $SkipWindowsChecks) {
    try {
        # Win32_LogicalDisk: DriveType 3 = Local Fixed Disk
        $disks = Get-CimInstance -ClassName Win32_LogicalDisk `
                     @cimArgs `
                     -Filter 'DriveType = 3' `
                     -ErrorAction Stop

        $volumeData = foreach ($disk in $disks) {
            $sizeGB  = if ($disk.Size -gt 0) { [math]::Round($disk.Size   / 1GB, 2) } else { 0 }
            $freeGB  = if ($disk.Size -gt 0) { [math]::Round($disk.FreeSpace / 1GB, 2) } else { 0 }
            $freePct = if ($sizeGB -gt 0)    { [math]::Round($freeGB / $sizeGB * 100, 1) } else { 0 }

            [PSCustomObject]@{
                ComputerName = $computerName
                DeviceID     = $disk.DeviceID
                VolumeName   = $disk.VolumeName
                DriveType    = $disk.DriveType
                SizeGB       = $sizeGB
                FreeGB       = $freeGB
                FreePct      = $freePct
                FileSystem   = $disk.FileSystem
                # WARNING: FreePct < 15%; CRITICAL: FreePct < 10%
                FreeSpaceFlag = if ($freePct -lt 10) { 'CRITICAL' }
                                elseif ($freePct -lt 15) { 'WARNING' }
                                else { 'OK' }
            }
        }

        # Also surface mount points via Get-PSDrive (local session only)
        # Get-PSDrive cannot target remote computers, so only include when
        # the target matches the local machine.
        $localNames = @($env:COMPUTERNAME, '.', '(local)', 'localhost')
        $mountData  = @()
        if ($computerName -in $localNames) {
            try {
                $mountData = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
                    Where-Object { $_.Root -match '^[A-Za-z]:\\' -or $_.DisplayRoot } |
                    Select-Object `
                        @{N='ComputerName'; E={ $computerName }},
                        @{N='DeviceID';     E={ $_.Name }},
                        @{N='VolumeName';   E={ $_.Description }},
                        @{N='DriveType';    E={ 'MountPoint' }},
                        @{N='SizeGB';       E={ if ($_.Used + $_.Free -gt 0) { [math]::Round(($_.Used + $_.Free) / 1GB, 2) } else { $null } }},
                        @{N='FreeGB';       E={ if ($_.Free -gt 0)           { [math]::Round($_.Free / 1GB, 2) }             else { $null } }},
                        @{N='FreePct';      E={
                            $total = $_.Used + $_.Free
                            if ($total -gt 0) { [math]::Round($_.Free / $total * 100, 1) } else { $null }
                        }},
                        @{N='FileSystem';   E={ $null }},
                        @{N='FreeSpaceFlag';E={
                            $total = $_.Used + $_.Free
                            if ($total -le 0) { 'UNKNOWN' }
                            else {
                                $pct = $_.Free / $total * 100
                                if ($pct -lt 10) { 'CRITICAL' } elseif ($pct -lt 15) { 'WARNING' } else { 'OK' }
                            }
                        }}
            }
            catch {
                # Get-PSDrive failure is non-fatal
                Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '05_01' `
                    -Status 'WARN' -Message "Get-PSDrive mount point enumeration failed: $($_.Exception.Message)"
            }
        }

        $allVolumes = @($volumeData) + @($mountData) | Where-Object { $_ -ne $null }

        $results.Add((Invoke-HCNativeSection `
            -Data        $allVolumes `
            -OutputPath  $OutputPath `
            -SectionId   '05_01' `
            -SectionName 'volume_capacity' `
            -Chapter     $chapter `
            -SqlInstance $SqlInstance))
    }
    catch {
        Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '05_01' `
            -Status 'ERROR' -Message "Volume capacity check failed: $($_.Exception.Message)"
    }
}
else {
    Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '05_01' `
        -Status 'SKIP' -Message 'Windows checks skipped (-SkipWindowsChecks).'
}

# ── 5.2 File inventory (SQL) ──────────────────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     $SqlDb `
    -SqlFile      (Join-Path $sqlDir '05_02_file_inventory.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '05_02' `
    -SectionName  'file_inventory' `
    -Chapter      $chapter `
    -QueryTimeout 600))

# ── 5.3 Autogrowth and shrink events (SQL) ────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     $SqlDb `
    -SqlFile      (Join-Path $sqlDir '05_03_autogrowth_shrink.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '05_03' `
    -SectionName  'autogrowth_shrink' `
    -Chapter      $chapter))

# ── 5.4 Disk sector and allocation unit size (PS-native via CIM/WMI) ──────────
if (-not $SkipWindowsChecks) {
    try {
        # Win32_Volume provides AllocationUnitSize and DriveLetter/DeviceID.
        $volumes = Get-CimInstance -ClassName Win32_Volume `
                       @cimArgs `
                       -ErrorAction Stop |
                   Where-Object { $_.DriveType -eq 3 }  # Fixed local

        $sectorData = foreach ($vol in $volumes) {
            $auSize = $vol.BlockSize   # BlockSize = allocation unit size in bytes

            # Flag: SQL Server documentation and Microsoft best practices
            # recommend a 64 KB (65536 byte) NTFS allocation unit size for
            # volumes hosting SQL Server data and log files.
            $flag = if ($auSize -ne $null -and $auSize -ne 65536) {
                        'WARNING: Allocation unit size is not 64 KB; '  +
                        'recommended 65536 bytes for SQL Server volumes.'
                    }
                    elseif ($auSize -eq $null) { 'UNKNOWN: Could not determine allocation unit size.' }
                    else                        { 'OK' }

            [PSCustomObject]@{
                ComputerName       = $computerName
                DeviceName         = $vol.DeviceID
                VolumePath         = if ($vol.DriveLetter) { $vol.DriveLetter } else { $vol.Name }
                AllocationUnitSize = $auSize
                DriveType          = $vol.DriveType
                FileSystem         = $vol.FileSystem
                CapacityGB         = if ($vol.Capacity -gt 0) { [math]::Round($vol.Capacity / 1GB, 2) } else { 0 }
                AllocationUnitFlag = $flag
            }
        }

        # Supplement with Win32_DiskPartition for sector size (bytes per sector).
        # Sector size is a property of the physical disk; surfaces via Win32_DiskDrive.
        $diskDrives = Get-CimInstance -ClassName Win32_DiskDrive `
                          @cimArgs `
                          -ErrorAction SilentlyContinue

        $sectorSizeMap = @{}
        if ($diskDrives) {
            foreach ($drive in $diskDrives) {
                $sectorSizeMap[$drive.DeviceID] = $drive.BytesPerSector
            }
        }

        # Try fsutil locally for additional detail if running on the target machine
        $localNames2 = @($env:COMPUTERNAME, '.', '(local)', 'localhost')
        if ($computerName -in $localNames2 -and @($sectorData).Count -gt 0) {
            foreach ($row in $sectorData) {
                $driveLetter = ($row.VolumePath -replace '[:\\]', '').Trim()
                if ($driveLetter -match '^[A-Za-z]$') {
                    try {
                        $fsutilOut = & fsutil fsinfo ntfsinfo "${driveLetter}:" 2>$null
                        $bytesPerSectorLine = $fsutilOut | Where-Object { $_ -match 'Bytes Per Sector' }
                        if ($bytesPerSectorLine) {
                            $row | Add-Member -NotePropertyName 'SectorSize' `
                                -NotePropertyValue ([int]($bytesPerSectorLine -replace '.*:\s*', '').Trim()) `
                                -Force
                        }
                        $bytesPerClusterLine = $fsutilOut | Where-Object { $_ -match 'Bytes Per Cluster' }
                        if ($bytesPerClusterLine) {
                            $bytesPerCluster = [int]($bytesPerClusterLine -replace '.*:\s*', '').Trim()
                            # Prefer fsutil result over WMI BlockSize when available
                            $row | Add-Member -NotePropertyName 'AllocationUnitSizeFsutil' `
                                -NotePropertyValue $bytesPerCluster `
                                -Force
                        }
                    }
                    catch {
                        # fsutil failure is non-fatal
                    }
                }
            }
        }

        $results.Add((Invoke-HCNativeSection `
            -Data        $sectorData `
            -OutputPath  $OutputPath `
            -SectionId   '05_04' `
            -SectionName 'disk_sector_size' `
            -Chapter     $chapter `
            -SqlInstance $SqlInstance))
    }
    catch {
        Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '05_04' `
            -Status 'ERROR' -Message "Disk sector/allocation unit check failed: $($_.Exception.Message)"
    }
}
else {
    Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '05_04' `
        -Status 'SKIP' -Message 'Windows checks skipped (-SkipWindowsChecks).'
}

# ── 5.5 File I/O latency (SQL) ────────────────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     $SqlDb `
    -SqlFile      (Join-Path $sqlDir '05_05_file_io_latency.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '05_05' `
    -SectionName  'file_io_latency' `
    -Chapter      $chapter))

# ── 5.6 Storage subsystem — MPIO and physical disk info (PS-native) ───────────
if (-not $SkipWindowsChecks) {
    try {
        $subsystemRows = [System.Collections.Generic.List[PSCustomObject]]::new()

        # ── Physical disk info via Get-PhysicalDisk (Storage module, local only) ──
        # Get-PhysicalDisk does not support -CimSession in all PowerShell versions;
        # limit to local execution to avoid remoting complexity.
        $localNames3 = @($env:COMPUTERNAME, '.', '(local)', 'localhost')
        if ($computerName -in $localNames3) {
            try {
                $physDisks = Get-PhysicalDisk -ErrorAction Stop
                foreach ($pd in $physDisks) {
                    $subsystemRows.Add([PSCustomObject]@{
                        ComputerName      = $computerName
                        DataSource        = 'Get-PhysicalDisk'
                        DeviceId          = $pd.DeviceId
                        FriendlyName      = $pd.FriendlyName
                        MediaType         = $pd.MediaType
                        BusType           = $pd.BusType
                        OperationalStatus = $pd.OperationalStatus
                        HealthStatus      = $pd.HealthStatus
                        SizeGB            = [math]::Round($pd.Size / 1GB, 2)
                        SpindleSpeed      = $pd.SpindleSpeed
                        FirmwareVersion   = $pd.FirmwareVersion
                        MPIOInstalled     = $null
                        MPIOPolicy        = $null
                        Note              = $null
                    })
                }
            }
            catch {
                $subsystemRows.Add([PSCustomObject]@{
                    ComputerName  = $computerName
                    DataSource    = 'Get-PhysicalDisk'
                    Note          = "Get-PhysicalDisk not available or failed: $($_.Exception.Message)"
                })
            }
        }
        else {
            $subsystemRows.Add([PSCustomObject]@{
                ComputerName = $computerName
                DataSource   = 'Get-PhysicalDisk'
                Note         = 'Get-PhysicalDisk remote execution not supported; run locally on target server.'
            })
        }

        # ── MPIO status via registry (works remotely via CIM) ─────────────────
        # The msdsm (Microsoft DSM) and mpio services presence in the registry
        # indicates MPIO is installed. The load balance policy is stored under
        # HKLM:\SYSTEM\CurrentControlSet\Services\msdsm\Parameters.
        $mpioInstalled = $false
        $mpioPolicy    = $null
        $mpioNote      = $null

        try {
            # Try Get-MpioSetting (MPIO feature module — local only)
            if ($computerName -in $localNames3) {
                $mpioSetting = Get-MpioSetting -ErrorAction Stop
                $mpioInstalled = $true
                $mpioPolicy    = $mpioSetting.PathVerificationState
                $mpioNote      = 'Retrieved via Get-MpioSetting'
            }
        }
        catch {
            # Get-MpioSetting not available — fall back to registry check
            $mpioNote = 'Get-MpioSetting not available; falling back to registry check.'
        }

        if (-not $mpioInstalled) {
            try {
                # Check for msdsm service via CIM (works remotely)
                $msdsmSvc = Get-CimInstance -ClassName Win32_Service `
                                @cimArgs `
                                -Filter "Name = 'msdsm'" `
                                -ErrorAction SilentlyContinue

                $mpioSvc = Get-CimInstance -ClassName Win32_Service `
                               @cimArgs `
                               -Filter "Name = 'mpio'" `
                               -ErrorAction SilentlyContinue

                if ($msdsmSvc -or $mpioSvc) {
                    $mpioInstalled = $true
                    $mpioNote      = 'MPIO detected via Win32_Service (msdsm/mpio service present).'
                }
                else {
                    $mpioNote = 'MPIO services (msdsm, mpio) not found; MPIO may not be installed.'
                }
            }
            catch {
                $mpioNote = "Registry/CIM MPIO check failed: $($_.Exception.Message)"
            }
        }

        $subsystemRows.Add([PSCustomObject]@{
            ComputerName      = $computerName
            DataSource        = 'MPIO'
            DeviceId          = $null
            FriendlyName      = $null
            MediaType         = $null
            BusType           = $null
            OperationalStatus = $null
            HealthStatus      = $null
            SizeGB            = $null
            SpindleSpeed      = $null
            FirmwareVersion   = $null
            MPIOInstalled     = $mpioInstalled
            MPIOPolicy        = $mpioPolicy
            Note              = $mpioNote
        })

        $results.Add((Invoke-HCNativeSection `
            -Data        $subsystemRows `
            -OutputPath  $OutputPath `
            -SectionId   '05_06' `
            -SectionName 'storage_subsystem' `
            -Chapter     $chapter `
            -SqlInstance $SqlInstance))
    }
    catch {
        Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '05_06' `
            -Status 'ERROR' -Message "Storage subsystem check failed: $($_.Exception.Message)"
    }
}
else {
    Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '05_06' `
        -Status 'SKIP' -Message 'Windows checks skipped (-SkipWindowsChecks).'
}

# ── 5.7 Instant File Initialization (SQL) ────────────────────────────────────
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     $SqlDb `
    -SqlFile      (Join-Path $sqlDir '05_07_instant_file_init.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '05_07' `
    -SectionName  'instant_file_init' `
    -Chapter      $chapter))

return $results
