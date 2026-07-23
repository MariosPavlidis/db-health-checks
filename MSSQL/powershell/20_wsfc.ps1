# =============================================================================
# 20_wsfc.ps1 — Chapter 20: Windows Server Failover Cluster
# Checklist sections: 20.1 – 20.6
# All sections are PS-native (FailoverClusters module). The entire chapter is
# skipped when -SkipWindowsChecks is set. Requires the FailoverClusters module
# (RSAT-Clustering feature) to be installed on the machine running this script.
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
$chapter = '20_wsfc'

. (Join-Path $PSScriptRoot 'shared\HC-Helpers.ps1')

$results = [System.Collections.Generic.List[PSCustomObject]]::new()

# ── Skip guard ────────────────────────────────────────────────────────────────
if ($SkipWindowsChecks) {
    $sections = @(
        @{ Id = '20_01'; Name = 'cluster_overview' },
        @{ Id = '20_02'; Name = 'cluster_quorum' },
        @{ Id = '20_03'; Name = 'node_ownership' },
        @{ Id = '20_04'; Name = 'cluster_networks' },
        @{ Id = '20_05'; Name = 'cluster_thresholds' },
        @{ Id = '20_06'; Name = 'cluster_events' }
    )
    foreach ($s in $sections) {
        Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section $s.Id `
            -Status 'SKIP' -Message 'Windows checks skipped (-SkipWindowsChecks).'
    }
    return $results
}

# ── FailoverClusters module check ─────────────────────────────────────────────
if (-not (Get-Module -ListAvailable FailoverClusters)) {
    Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '20_01' `
        -Status 'SKIP' -Message 'FailoverClusters module not available. Install RSAT-Clustering feature.'
    return $results
}

Import-Module FailoverClusters -ErrorAction Stop

# Resolve cluster — attempt to discover from the SQL instance host
$computerName = ($SqlInstance -split '\\')[0]
if ($computerName -in @('.', '(local)', 'localhost')) { $computerName = $env:COMPUTERNAME }

# ── 20.1 Cluster overview ──────────────────────────────────────────────────────
try {
    # Try local cluster service first (most reliable on a cluster node,
    # and avoids WMI token issues when running inside Start-Job).
    $clusterErrVar = @()
    $cluster = Get-Cluster -ErrorAction SilentlyContinue -ErrorVariable +clusterErrVar
    if (-not $cluster) {
        $cluster = Get-Cluster -Name $computerName -ErrorAction SilentlyContinue -ErrorVariable +clusterErrVar
    }

    if ($cluster) {
        $nodes     = Get-ClusterNode     -Cluster $cluster -ErrorAction SilentlyContinue
        $groups    = Get-ClusterGroup    -Cluster $cluster -ErrorAction SilentlyContinue
        $resources = Get-ClusterResource -Cluster $cluster -ErrorAction SilentlyContinue

        $nodeRows = $nodes | Select-Object `
            @{N='ClusterName';   E={ $cluster.Name }},
            @{N='ObjectType';    E={ 'Node' }},
            Name, State,
            @{N='Detail';        E={ "NodeWeight=$($_.NodeWeight)" }},
            @{N='Flag';          E={ if ($_.State -ne 'Up') { 'NODE_NOT_UP' } else { '' } }}

        $groupRows = $groups | Select-Object `
            @{N='ClusterName';   E={ $cluster.Name }},
            @{N='ObjectType';    E={ 'Group' }},
            Name, State,
            @{N='Detail';        E={ "OwnerNode=$($_.OwnerNode)" }},
            @{N='Flag';          E={ if ($_.State -notmatch 'Online|Partial') { 'GROUP_OFFLINE' } else { '' } }}

        $resourceRows = $resources | Select-Object `
            @{N='ClusterName';   E={ $cluster.Name }},
            @{N='ObjectType';    E={ 'Resource' }},
            Name, State,
            @{N='Detail';        E={ "ResourceType=$($_.ResourceType); OwnerGroup=$($_.OwnerGroup); OwnerNode=$($_.OwnerNode)" }},
            @{N='Flag';          E={ if ($_.State -notmatch 'Online|Inherited') { 'RESOURCE_OFFLINE' } else { '' } }}

        $clusterSummary = [PSCustomObject]@{
            ClusterName      = $cluster.Name
            ObjectType       = 'ClusterSummary'
            Name             = $cluster.Name
            State            = 'N/A'
            Detail           = "FunctionalLevel=$($cluster.ClusterFunctionalLevel)"
            Flag             = ''
        }

        $overviewData = @($clusterSummary) + @($nodeRows) + @($groupRows) + @($resourceRows)

        $results.Add((Invoke-HCNativeSection `
            -Data        $overviewData `
            -OutputPath  $OutputPath `
            -SectionId   '20_01' `
            -SectionName 'cluster_overview' `
            -Chapter     $chapter `
            -SqlInstance $SqlInstance))
    }
    else {
        $errDetail = if ($clusterErrVar) { " Errors: $(($clusterErrVar | ForEach-Object { $_.Exception.Message }) -join '; ')" } else { '' }
        Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '20_01' `
            -Status 'WARN' -Message "No cluster found for host '$computerName'. Instance may not be clustered.$errDetail"
    }
}
catch {
    Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '20_01' `
        -Status 'ERROR' -Message "Cluster overview failed: $($_.Exception.Message)"
}

# ── 20.2 Quorum configuration ──────────────────────────────────────────────────
try {
    if ($cluster) {
        $quorum    = Get-ClusterQuorum -Cluster $cluster -ErrorAction SilentlyContinue
        $nodeVotes = Get-ClusterNode   -Cluster $cluster -ErrorAction SilentlyContinue |
                         Select-Object Name, State, NodeWeight, DynamicWeight, Vote

        $quorumSummary = [PSCustomObject]@{
            ClusterName  = $cluster.Name
            QuorumType   = if ($quorum) { $quorum.QuorumType }   else { $null }
            QuorumResource = if ($quorum) { $quorum.QuorumResource } else { $null }
        }

        $quorumData = @($quorumSummary) + @($nodeVotes)

        $results.Add((Invoke-HCNativeSection `
            -Data        $quorumData `
            -OutputPath  $OutputPath `
            -SectionId   '20_02' `
            -SectionName 'cluster_quorum' `
            -Chapter     $chapter `
            -SqlInstance $SqlInstance))
    }
    else {
        Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '20_02' `
            -Status 'SKIP' -Message 'No cluster object available — quorum check skipped.'
    }
}
catch {
    Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '20_02' `
        -Status 'ERROR' -Message "Quorum check failed: $($_.Exception.Message)"
}

# ── 20.3 Node ownership for SQL Server resources ───────────────────────────────
try {
    if ($cluster) {
        $sqlResources = Get-ClusterResource -Cluster $cluster -ErrorAction SilentlyContinue |
                            Where-Object { $_.ResourceType.Name -eq 'SQL Server' }

        $ownerRows = if ($sqlResources) {
            $sqlResources | ForEach-Object {
                $res = $_
                try {
                    $owners = Get-ClusterOwnerNode -InputObject $res -ErrorAction SilentlyContinue
                    $owners | ForEach-Object {
                        [PSCustomObject]@{
                            ClusterName    = $cluster.Name
                            ResourceName   = $res.Name
                            OwnerNode      = $_.NodeName
                        }
                    }
                }
                catch {
                    [PSCustomObject]@{
                        ClusterName  = $cluster.Name
                        ResourceName = $res.Name
                        OwnerNode    = "Error: $($_.Exception.Message)"
                    }
                }
            }
        } else {
            [PSCustomObject]@{
                ClusterName  = $cluster.Name
                ResourceName = 'No SQL Server cluster resources found'
                OwnerNode    = $null
            }
        }

        $results.Add((Invoke-HCNativeSection `
            -Data        $ownerRows `
            -OutputPath  $OutputPath `
            -SectionId   '20_03' `
            -SectionName 'node_ownership' `
            -Chapter     $chapter `
            -SqlInstance $SqlInstance))
    }
    else {
        Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '20_03' `
            -Status 'SKIP' -Message 'No cluster object available — node ownership check skipped.'
    }
}
catch {
    Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '20_03' `
        -Status 'ERROR' -Message "Node ownership check failed: $($_.Exception.Message)"
}

# ── 20.4 Cluster networks ──────────────────────────────────────────────────────
try {
    if ($cluster) {
        $networks = Get-ClusterNetwork -Cluster $cluster -ErrorAction SilentlyContinue |
                        Select-Object `
                            @{N='ClusterName'; E={ $cluster.Name }},
                            Name, Role, Metric, State, Address, AddressMask, IPv6Addresses,
                            @{N='Flag'; E={
                                if ($_.State -ne 'Up') { 'NETWORK_NOT_UP' }
                                elseif ($_.Role -eq 0) { 'NETWORK_NO_ROLE' }
                                else { '' }
                            }}

        $results.Add((Invoke-HCNativeSection `
            -Data        $networks `
            -OutputPath  $OutputPath `
            -SectionId   '20_04' `
            -SectionName 'cluster_networks' `
            -Chapter     $chapter `
            -SqlInstance $SqlInstance))
    }
    else {
        Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '20_04' `
            -Status 'SKIP' -Message 'No cluster object available — network check skipped.'
    }
}
catch {
    Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '20_04' `
        -Status 'ERROR' -Message "Cluster network check failed: $($_.Exception.Message)"
}

# ── 20.5 Cluster heartbeat thresholds ─────────────────────────────────────────
try {
    if ($cluster) {
        $thresholds = [PSCustomObject]@{
            ClusterName              = $cluster.Name
            SameSubnetDelay          = (Get-ClusterParameter -Cluster $cluster -Name SameSubnetDelay      -ErrorAction SilentlyContinue).Value
            SameSubnetThreshold      = (Get-ClusterParameter -Cluster $cluster -Name SameSubnetThreshold  -ErrorAction SilentlyContinue).Value
            CrossSubnetDelay         = (Get-ClusterParameter -Cluster $cluster -Name CrossSubnetDelay     -ErrorAction SilentlyContinue).Value
            CrossSubnetThreshold     = (Get-ClusterParameter -Cluster $cluster -Name CrossSubnetThreshold -ErrorAction SilentlyContinue).Value
            QuorumArbitrationTimeMax = (Get-ClusterParameter -Cluster $cluster -Name QuorumArbitrationTimeMax -ErrorAction SilentlyContinue).Value
            HealthCheckTimeout       = (Get-ClusterParameter -Cluster $cluster -Name HealthCheckTimeout   -ErrorAction SilentlyContinue).Value
        }

        $results.Add((Invoke-HCNativeSection `
            -Data        $thresholds `
            -OutputPath  $OutputPath `
            -SectionId   '20_05' `
            -SectionName 'cluster_thresholds' `
            -Chapter     $chapter `
            -SqlInstance $SqlInstance))
    }
    else {
        Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '20_05' `
            -Status 'SKIP' -Message 'No cluster object available — threshold check skipped.'
    }
}
catch {
    Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '20_05' `
        -Status 'ERROR' -Message "Cluster threshold check failed: $($_.Exception.Message)"
}

# ── 20.6 Cluster operational events (last 90 days) ────────────────────────────
try {
    $startTime = (Get-Date).AddDays(-90)

    $clusterEvents = Get-WinEvent -ComputerName $computerName -FilterHashtable @{
        LogName   = 'Microsoft-Windows-FailoverClustering/Operational'
        Level     = @(1, 2, 3)   # Critical, Error, Warning
        StartTime = $startTime
    } -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Id, LevelDisplayName, ProviderName,
        @{N='ComputerName'; E={ $computerName }},
        @{N='Message';      E={ $_.Message -replace '\r\n', ' ' }}

    $results.Add((Invoke-HCNativeSection `
        -Data        $clusterEvents `
        -OutputPath  $OutputPath `
        -SectionId   '20_06' `
        -SectionName 'cluster_events' `
        -Chapter     $chapter `
        -SqlInstance $SqlInstance))
}
catch {
    Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '20_06' `
        -Status 'ERROR' -Message "Cluster event log check failed: $($_.Exception.Message)"
}

return $results
