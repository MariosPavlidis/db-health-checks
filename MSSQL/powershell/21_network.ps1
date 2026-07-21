# =============================================================================
# 21_network.ps1 — Chapter 21: Network Health
# Checklist sections: 21.01, 21.01b, 21.02
# SQL sections use Invoke-HCSqlText (inline queries — no sql/21 folder).
# PS-native sections are skipped when -SkipWindowsChecks is set.
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
$chapter = '21_network'

. (Join-Path $PSScriptRoot 'shared\HC-Helpers.ps1')

Ensure-HCSqlModule

$results  = [System.Collections.Generic.List[PSCustomObject]]::new()
$sqlSplat = @{ SqlInstance = $SqlInstance; Database = 'master' }
if ($SqlCredential) { $sqlSplat['SqlCredential'] = $SqlCredential }

$computerName = ($SqlInstance -split '\\')[0]
if ($computerName -in @('.', '(local)', 'localhost')) { $computerName = $env:COMPUTERNAME }

# ── 21.01 Connection failures and transport errors from SQL error log ──────────
try {
    $sql = @"
CREATE TABLE #NetErrors (LogDate DATETIME, ProcessInfo VARCHAR(100), [Text] NVARCHAR(4000));
INSERT INTO #NetErrors EXEC master.dbo.xp_readerrorlog 0, 1, N'connection';
INSERT INTO #NetErrors EXEC master.dbo.xp_readerrorlog 0, 1, N'timeout';
INSERT INTO #NetErrors EXEC master.dbo.xp_readerrorlog 0, 1, N'transport';
SELECT DISTINCT TOP 200
    LogDate,
    ProcessInfo,
    [Text]
FROM #NetErrors
ORDER BY LogDate DESC;
DROP TABLE #NetErrors;
"@

    $dt = Invoke-HCSqlText @sqlSplat -Query $sql -QueryTimeout 120

    $results.Add((Invoke-HCNativeSection `
        -Data        $dt `
        -OutputPath  $OutputPath `
        -SectionId   '21_01' `
        -SectionName 'connection_errors' `
        -Chapter     $chapter `
        -SqlInstance $SqlInstance))
}
catch {
    Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '21_01' `
        -Status 'ERROR' -Message "Connection error log check failed: $($_.Exception.Message)"
}

# ── 21.01b SQL Server listening port (SQL inline) ─────────────────────────────
try {
    $portQuery = @"
SELECT
    local_net_address   AS LocalNetAddress,
    local_tcp_port      AS LocalTcpPort,
    net_transport       AS NetTransport,
    client_net_address  AS ClientNetAddress
FROM sys.dm_exec_connections
WHERE session_id = @@SPID;
"@

    $portDt = Invoke-HCSqlText @sqlSplat -Query $portQuery

    $results.Add((Invoke-HCNativeSection `
        -Data        $portDt `
        -OutputPath  $OutputPath `
        -SectionId   '21_01b' `
        -SectionName 'listening_port' `
        -Chapter     $chapter `
        -SqlInstance $SqlInstance))
}
catch {
    Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '21_01b' `
        -Status 'ERROR' -Message "Listening port check failed: $($_.Exception.Message)"
}

# ── 21.02 Cross-site network evidence (PS-native) ─────────────────────────────
if (-not $SkipWindowsChecks) {
    try {
        # Basic TCP connectivity test to SQL Server port
        $testResult = Test-NetConnection -ComputerName $computerName -Port 1433 `
                          -WarningAction SilentlyContinue -ErrorAction SilentlyContinue

        # ICMP round-trip time
        $ping      = [System.Net.NetworkInformation.Ping]::new()
        $pingReply = $ping.Send($computerName, 1000)

        # Active network adapters
        $adapters  = Get-NetAdapter -ErrorAction SilentlyContinue |
                         Where-Object { $_.Status -eq 'Up' } |
                         Select-Object Name, InterfaceDescription, MacAddress, LinkSpeed,
                             FullDuplex, MediaConnectionState, DriverInformation

        $connectivityData = [PSCustomObject]@{
            ComputerName            = $computerName
            TcpTestPort             = 1433
            TcpTestSucceeded        = if ($testResult) { $testResult.TcpTestSucceeded } else { $null }
            PingStatus              = if ($pingReply)  { $pingReply.Status.ToString() }  else { 'N/A' }
            PingRoundTripMs         = if ($pingReply -and $pingReply.Status -eq 'Success') { $pingReply.RoundtripTime } else { $null }
            PingBufferSize          = if ($pingReply -and $pingReply.Status -eq 'Success') { $pingReply.Buffer.Length }  else { $null }
            RemoteAddress           = if ($testResult) { $testResult.RemoteAddress }    else { $null }
            InterfaceAlias          = if ($testResult) { $testResult.InterfaceAlias }   else { $null }
            SourceAddress           = if ($testResult -and $testResult.SourceAddress) { $testResult.SourceAddress.IPAddress } else { $null }
        }

        $adapterRows = if ($adapters) {
            @($adapters) | ForEach-Object {
                [PSCustomObject]@{
                    ComputerName          = $computerName
                    AdapterName           = $_.Name
                    Description           = $_.InterfaceDescription
                    MacAddress            = $_.MacAddress
                    LinkSpeed             = $_.LinkSpeed
                    FullDuplex            = $_.FullDuplex
                    MediaConnectionState  = $_.MediaConnectionState
                }
            }
        } else { @() }

        $networkData = @($connectivityData) + @($adapterRows)

        $results.Add((Invoke-HCNativeSection `
            -Data        $networkData `
            -OutputPath  $OutputPath `
            -SectionId   '21_02' `
            -SectionName 'network_connectivity' `
            -Chapter     $chapter `
            -SqlInstance $SqlInstance))
    }
    catch {
        Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '21_02' `
            -Status 'ERROR' -Message "Network connectivity check failed: $($_.Exception.Message)"
    }
}
else {
    Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '21_02' `
        -Status 'SKIP' -Message 'Windows checks skipped (-SkipWindowsChecks).'
}

return $results
