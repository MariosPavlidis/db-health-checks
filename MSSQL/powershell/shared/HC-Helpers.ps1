# =============================================================================
# HC-Helpers.ps1 — Shared helper functions for SQL Server Health Check scripts
# =============================================================================
# Dot-source this file at the top of every chapter script:
#   . "$PSScriptRoot\shared\HC-Helpers.ps1"
# =============================================================================

#region ── Invoke-HCSql ───────────────────────────────────────────────────────
function Invoke-HCSql {
    <#
    .SYNOPSIS
        Execute a .sql file against a SQL Server instance and return results as a DataTable.
    .PARAMETER SqlInstance
        SQL Server instance name (e.g. "SERVER01" or "SERVER01\INST").
    .PARAMETER Database
        Target database context. Default: master.
    .PARAMETER SqlFile
        Full path to the .sql file to execute.
    .PARAMETER SqlCredential
        Optional PSCredential for SQL Authentication. If omitted, Windows Auth is used.
    .PARAMETER QueryTimeout
        Query timeout in seconds. Default: 120. Queries that exceed this are cancelled
        and logged as ERROR — matching the orchestrator chapter-level stall threshold.
    #>
    [CmdletBinding()]
    [OutputType([System.Data.DataTable])]
    param(
        [Parameter(Mandatory)][string]$SqlInstance,
        [string]$Database      = 'master',
        [Parameter(Mandatory)][string]$SqlFile,
        [System.Management.Automation.PSCredential]$SqlCredential,
        [int]$QueryTimeout     = 120
    )

    if (-not (Test-Path $SqlFile)) {
        throw "SQL file not found: $SqlFile"
    }

    $query = Get-Content -Path $SqlFile -Raw

    $splat = @{
        ServerInstance        = $SqlInstance
        Database              = $Database
        Query                 = $query
        QueryTimeout          = $QueryTimeout
        OutputSqlErrors       = $true
        TrustServerCertificate = $true
        ErrorAction           = 'Stop'
    }

    if ($SqlCredential) {
        $splat['Username'] = $SqlCredential.UserName
        $splat['Password'] = $SqlCredential.GetNetworkCredential().Password
    }

    $results = Invoke-Sqlcmd @splat

    # Convert to DataTable for consistent handling
    if ($null -eq $results) {
        return ,[System.Data.DataTable]::new()
    }

    $dt = [System.Data.DataTable]::new()
    foreach ($row in $results) {
        # Add any new columns from this row (handles multi-result-set SQL files)
        foreach ($prop in $row.PSObject.Properties) {
            if (-not $dt.Columns.Contains($prop.Name)) {
                [void]$dt.Columns.Add($prop.Name, [object])
            }
        }
        $dr = $dt.NewRow()
        foreach ($prop in $row.PSObject.Properties) {
            $dr[$prop.Name] = if ($null -eq $prop.Value) { [DBNull]::Value } else { $prop.Value }
        }
        [void]$dt.Rows.Add($dr)
    }

    return ,$dt
}
#endregion

#region ── Invoke-HCSqlText ───────────────────────────────────────────────────
function Invoke-HCSqlText {
    <#
    .SYNOPSIS
        Execute an inline SQL string (not a file). Used for dynamic queries in PS chapter scripts.
    #>
    [CmdletBinding()]
    [OutputType([System.Data.DataTable])]
    param(
        [Parameter(Mandatory)][string]$SqlInstance,
        [string]$Database      = 'master',
        [Parameter(Mandatory)][string]$Query,
        [System.Management.Automation.PSCredential]$SqlCredential,
        [int]$QueryTimeout     = 120
    )

    $splat = @{
        ServerInstance         = $SqlInstance
        Database               = $Database
        Query                  = $Query
        QueryTimeout           = $QueryTimeout
        OutputSqlErrors        = $true
        TrustServerCertificate = $true
        ErrorAction            = 'Stop'
    }

    if ($SqlCredential) {
        $splat['Username'] = $SqlCredential.UserName
        $splat['Password'] = $SqlCredential.GetNetworkCredential().Password
    }

    $results = Invoke-Sqlcmd @splat

    if ($null -eq $results) {
        return ,[System.Data.DataTable]::new()
    }

    $dt = [System.Data.DataTable]::new()
    foreach ($row in $results) {
        # Add any new columns from this row (handles multi-result-set SQL files)
        foreach ($prop in $row.PSObject.Properties) {
            if (-not $dt.Columns.Contains($prop.Name)) {
                [void]$dt.Columns.Add($prop.Name, [object])
            }
        }
        $dr = $dt.NewRow()
        foreach ($prop in $row.PSObject.Properties) {
            $dr[$prop.Name] = if ($null -eq $prop.Value) { [DBNull]::Value } else { $prop.Value }
        }
        [void]$dt.Rows.Add($dr)
    }

    return ,$dt
}
#endregion

#region ── Export-HCResult ────────────────────────────────────────────────────
function Export-HCResult {
    <#
    .SYNOPSIS
        Export a DataTable or array of PSObjects to a CSV file with standard metadata columns.
    .PARAMETER Data
        DataTable or PS object array to export.
    .PARAMETER OutputPath
        Folder path for the CSV. File is named {SectionId}_{SectionName}.csv.
    .PARAMETER SectionId
        Section identifier string, e.g. "01_01".
    .PARAMETER SectionName
        Human-readable section name for the filename, e.g. "cpu_numa_topology".
    .PARAMETER SqlInstance
        Instance name appended as metadata column.
    #>
    [CmdletBinding()]
    param(
        $Data,
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter(Mandatory)][string]$SectionId,
        [Parameter(Mandatory)][string]$SectionName,
        [string]$SqlInstance = ''
    )

    $fileName  = "${SectionId}_${SectionName}.csv"
    $filePath  = Join-Path $OutputPath $fileName
    $timestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

    if ($null -eq $Data -or ($Data -is [System.Data.DataTable] -and $Data.Rows.Count -eq 0) `
        -or ($Data -isnot [System.Data.DataTable] -and @($Data).Count -eq 0)) {
        # Write a single-row CSV indicating no data returned
        [PSCustomObject]@{
            CollectedAt = $timestamp
            SqlInstance = $SqlInstance
            Note        = 'No data returned'
        } | Export-Csv -Path $filePath -NoTypeInformation -Encoding UTF8
        return $filePath
    }

    if ($Data -is [System.Data.DataTable]) {
        $rows = foreach ($row in $Data.Rows) {
            $obj = [ordered]@{}
            foreach ($col in $Data.Columns) {
                $val = $row[$col.ColumnName]
                $obj[$col.ColumnName] = if ($val -is [DBNull]) { $null } else { $val }
            }
            $obj['CollectedAt'] = $timestamp
            $obj['SqlInstance'] = $SqlInstance
            [PSCustomObject]$obj
        }
    } else {
        $rows = @($Data) | Select-Object *,
            @{N='CollectedAt';E={$timestamp}},
            @{N='SqlInstance';E={$SqlInstance}}
    }

    $rows | Export-Csv -Path $filePath -NoTypeInformation -Encoding UTF8
    return $filePath
}
#endregion

#region ── Get-HCSqlVersion ───────────────────────────────────────────────────
function Get-HCSqlVersion {
    <#
    .SYNOPSIS
        Return the SQL Server major version as an integer (e.g. 13 for SQL 2016).
    #>
    [OutputType([int])]
    param(
        [Parameter(Mandatory)][string]$SqlInstance,
        [System.Management.Automation.PSCredential]$SqlCredential
    )

    $splat = @{ SqlInstance = $SqlInstance }
    if ($SqlCredential) { $splat['SqlCredential'] = $SqlCredential }

    $dt = Invoke-HCSqlText @splat -Query "SELECT CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) AS [MajorVersion];"
    if ($dt.Rows.Count -gt 0) {
        return [int]$dt.Rows[0]['MajorVersion']
    }
    return 0
}
#endregion

#region ── Test-HCHadr ────────────────────────────────────────────────────────
function Test-HCHadr {
    <#
    .SYNOPSIS
        Return $true if HADR (Always On AG) is enabled on the instance.
    #>
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$SqlInstance,
        [System.Management.Automation.PSCredential]$SqlCredential
    )

    $splat = @{ SqlInstance = $SqlInstance }
    if ($SqlCredential) { $splat['SqlCredential'] = $SqlCredential }

    $dt = Invoke-HCSqlText @splat -Query "SELECT CAST(SERVERPROPERTY('IsHadrEnabled') AS INT) AS [HadrEnabled];"
    if ($dt.Rows.Count -gt 0) {
        return [int]$dt.Rows[0]['HadrEnabled'] -eq 1
    }
    return $false
}
#endregion

#region ── Write-HCLog ────────────────────────────────────────────────────────
function Write-HCLog {
    <#
    .SYNOPSIS
        Append a structured entry to the health check run log.
    .PARAMETER OutputPath
        Folder path containing hc_run.log.
    .PARAMETER Chapter
        Chapter number/name label, e.g. "01_cpu_numa_memory".
    .PARAMETER Section
        Section label, e.g. "01_01".
    .PARAMETER Status
        One of: INFO, OK, WARN, ERROR, SKIP.
    .PARAMETER Message
        Log message text.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$OutputPath,
        [string]$Chapter = '',
        [string]$Section = '',
        [ValidateSet('INFO','OK','WARN','ERROR','SKIP','PARTIAL','TIMEOUT')]
        [string]$Status  = 'INFO',
        [Parameter(Mandatory)][string]$Message
    )

    $logFile = Join-Path $OutputPath 'hc_run.log'
    $ts      = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $line    = "[$ts] [$Status] [$Chapter] [$Section] $Message"

    Add-Content -Path $logFile -Value $line -Encoding Unicode

    # Also write to console with colour
    $colour = switch ($Status) {
        'OK'      { 'Green'   }
        'WARN'    { 'Yellow'  }
        'ERROR'   { 'Red'     }
        'SKIP'    { 'Cyan'    }
        'PARTIAL' { 'Magenta' }
        'TIMEOUT' { 'Red'     }
        default   { 'Gray'    }
    }
    Write-Host $line -ForegroundColor $colour
}
#endregion

#region ── Invoke-HCSection ───────────────────────────────────────────────────
function Invoke-HCSection {
    <#
    .SYNOPSIS
        Convenience wrapper: run a SQL file, export result, log outcome.
        Returns a result summary hashtable.
    .PARAMETER SqlInstance
        SQL Server instance.
    .PARAMETER Database
        Database context. Default: master.
    .PARAMETER SqlFile
        Path to the .sql script file.
    .PARAMETER OutputPath
        Output folder.
    .PARAMETER SectionId
        e.g. "01_01"
    .PARAMETER SectionName
        e.g. "cpu_numa_topology"
    .PARAMETER Chapter
        e.g. "01_cpu_numa_memory"
    .PARAMETER SqlCredential
        Optional SQL credential.
    .PARAMETER QueryTimeout
        Seconds before the SQL query is cancelled. Default 120.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SqlInstance,
        [string]$Database      = 'master',
        [Parameter(Mandatory)][string]$SqlFile,
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter(Mandatory)][string]$SectionId,
        [Parameter(Mandatory)][string]$SectionName,
        [string]$Chapter       = '',
        [System.Management.Automation.PSCredential]$SqlCredential,
        [int]$QueryTimeout     = 120
    )

    $result = [PSCustomObject]@{
        SectionId   = $SectionId
        SectionName = $SectionName
        Status      = 'OK'
        CsvFile     = ''
        Error       = ''
    }

    try {
        $splat = @{
            SqlInstance  = $SqlInstance
            Database     = $Database
            SqlFile      = $SqlFile
            QueryTimeout = $QueryTimeout
        }
        if ($SqlCredential) { $splat['SqlCredential'] = $SqlCredential }

        $dt = Invoke-HCSql @splat

        $exportSplat = @{
            Data        = $dt
            OutputPath  = $OutputPath
            SectionId   = $SectionId
            SectionName = $SectionName
            SqlInstance = $SqlInstance
        }
        $csvPath = Export-HCResult @exportSplat
        $result.CsvFile = $csvPath

        Write-HCLog -OutputPath $OutputPath -Chapter $Chapter -Section $SectionId `
            -Status 'OK' -Message "Exported $($dt.Rows.Count) rows → $(Split-Path $csvPath -Leaf)"
    }
    catch {
        $result.Status = 'ERROR'
        $result.Error  = $_.Exception.Message
        Write-HCLog -OutputPath $OutputPath -Chapter $Chapter -Section $SectionId `
            -Status 'ERROR' -Message $_.Exception.Message
    }

    return $result
}
#endregion

#region ── Invoke-HCNativeSection ─────────────────────────────────────────────
function Invoke-HCNativeSection {
    <#
    .SYNOPSIS
        Convenience wrapper for PS-native (non-SQL) sections: export result, log outcome.
    .PARAMETER Data
        PS object array or DataTable to export.
    .PARAMETER OutputPath
        Output folder.
    .PARAMETER SectionId
        e.g. "01_05"
    .PARAMETER SectionName
        e.g. "os_memory_paging"
    .PARAMETER Chapter
        e.g. "01_cpu_numa_memory"
    .PARAMETER SqlInstance
        Instance name for metadata column.
    #>
    [CmdletBinding()]
    param(
        $Data,
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter(Mandatory)][string]$SectionId,
        [Parameter(Mandatory)][string]$SectionName,
        [string]$Chapter    = '',
        [string]$SqlInstance = ''
    )

    $result = [PSCustomObject]@{
        SectionId   = $SectionId
        SectionName = $SectionName
        Status      = 'OK'
        CsvFile     = ''
        Error       = ''
    }

    try {
        $csvPath = Export-HCResult -Data $Data -OutputPath $OutputPath `
            -SectionId $SectionId -SectionName $SectionName -SqlInstance $SqlInstance
        $result.CsvFile = $csvPath
        $count = if ($Data -is [System.Data.DataTable]) { $Data.Rows.Count } else { @($Data).Count }
        Write-HCLog -OutputPath $OutputPath -Chapter $Chapter -Section $SectionId `
            -Status 'OK' -Message "Exported $count rows → $(Split-Path $csvPath -Leaf)"
    }
    catch {
        $result.Status = 'ERROR'
        $result.Error  = $_.Exception.Message
        Write-HCLog -OutputPath $OutputPath -Chapter $Chapter -Section $SectionId `
            -Status 'ERROR' -Message $_.Exception.Message
    }

    return $result
}
#endregion

#region ── Ensure-HCSqlModule ─────────────────────────────────────────────────
function Ensure-HCSqlModule {
    <#
    .SYNOPSIS
        Verify the SqlServer module is available. Throw with install guidance if not.
    #>
    if (-not (Get-Module -ListAvailable -Name SqlServer)) {
        throw "The 'SqlServer' PowerShell module is required. Install it with: Install-Module SqlServer -Scope CurrentUser"
    }
    Import-Module SqlServer -ErrorAction Stop
}
#endregion
