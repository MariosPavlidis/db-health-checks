# =============================================================================
# 16_encryption_tls.ps1 — Chapter 16: Encryption, TLS, and Certificates
# Checklist sections: 16.1 – 16.4
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
$chapter  = '16_encryption_tls'
$sqlDir   = Join-Path $SqlScriptRoot "sql\16_encryption_tls"

. (Join-Path $PSScriptRoot 'shared\HC-Helpers.ps1')

$results  = [System.Collections.Generic.List[PSCustomObject]]::new()
$sqlSplat = @{ SqlInstance = $SqlInstance }
if ($SqlCredential) { $sqlSplat['SqlCredential'] = $SqlCredential }

# ── 16.1 Network encryption ───────────────────────────────────────────────────
# Active connection encryption counts, ForceEncryption config, and the TLS
# certificate thumbprint configured in the registry (SuperSocketNetLib).
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     'master' `
    -SqlFile      (Join-Path $sqlDir '16_01_network_encryption.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '16_01' `
    -SectionName  'network_encryption' `
    -Chapter      $chapter))

# ── 16.1b Windows machine TLS certificates (PS-native) ───────────────────────
# Enumerates certificates in Cert:\LocalMachine\My that are marked for Server
# Authentication.  Flags those matching the SQL Server thumbprint from the
# registry, and classifies expiry using the same thresholds as the SQL checks.
if (-not $SkipWindowsChecks) {
    try {
        $computerName = ($SqlInstance -split '\\')[0]
        if ($computerName -in @('.', '(local)', 'localhost')) {
            $computerName = $env:COMPUTERNAME
        }

        # Attempt to read the SQL Server TLS certificate thumbprint from the registry
        # so we can flag which Windows cert SQL is actually using.
        $sqlThumbprint = $null
        try {
            $regPath   = 'SOFTWARE\Microsoft\Microsoft SQL Server\MSSQLServer\SuperSocketNetLib'
            $regResult = Invoke-HCSqlText @sqlSplat -Database 'master' -Query @"
DECLARE @thumb NVARCHAR(256) = NULL;
EXEC xp_instance_regread
    N'HKEY_LOCAL_MACHINE',
    N'$regPath',
    N'Certificate',
    @thumb OUTPUT;
SELECT ISNULL(@thumb, '') AS Thumbprint;
"@
            if ($regResult.Rows.Count -gt 0) {
                $sqlThumbprint = $regResult.Rows[0]['Thumbprint']
                if ([string]::IsNullOrWhiteSpace($sqlThumbprint)) { $sqlThumbprint = $null }
            }
        }
        catch {
            # Registry read failure is non-fatal; continue without thumbprint matching
        }

        # Enumerate Server Authentication certificates in the local machine store
        $certStore = if ($computerName -eq $env:COMPUTERNAME) {
            Get-ChildItem 'Cert:\LocalMachine\My' -ErrorAction Stop
        }
        else {
            # Remote certificate stores require CredSSP or PS remoting; attempt invoke
            Invoke-Command -ComputerName $computerName -ScriptBlock {
                Get-ChildItem 'Cert:\LocalMachine\My'
            } -ErrorAction Stop
        }

        $now     = Get-Date
        $certRows = $certStore |
            Where-Object {
                $_.EnhancedKeyUsageList -match 'Server Authentication' -or
                $_.Thumbprint -eq $sqlThumbprint
            } |
            ForEach-Object {
                $cert            = $_
                $daysUntilExpiry = [math]::Round(($cert.NotAfter - $now).TotalDays, 0)
                $expiryFlag      = switch ($true) {
                    ($cert.NotAfter -lt $now)        { 'EXPIRED';   break }
                    ($daysUntilExpiry -lt 30)        { 'CRITICAL';  break }
                    ($daysUntilExpiry -lt 90)        { 'HIGH';      break }
                    ($daysUntilExpiry -lt 180)       { 'WARNING';   break }
                    default                          { 'OK' }
                }

                [PSCustomObject]@{
                    ComputerName        = $computerName
                    Subject             = $cert.Subject
                    Issuer              = $cert.Issuer
                    Thumbprint          = $cert.Thumbprint
                    NotBefore           = $cert.NotBefore
                    NotAfter            = $cert.NotAfter
                    DaysUntilExpiry     = $daysUntilExpiry
                    HasPrivateKey       = $cert.HasPrivateKey
                    EnhancedKeyUsage    = ($cert.EnhancedKeyUsageList.FriendlyName -join '; ')
                    IsSqlServerCert     = ($cert.Thumbprint -eq $sqlThumbprint)
                    ExpiryFlag          = $expiryFlag
                    CertSource          = 'WINDOWS_MACHINE_STORE'
                }
            }

        $results.Add((Invoke-HCNativeSection `
            -Data        $certRows `
            -OutputPath  $OutputPath `
            -SectionId   '16_01b' `
            -SectionName 'windows_tls_certs' `
            -Chapter     $chapter `
            -SqlInstance $SqlInstance))
    }
    catch {
        Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '16_01b' `
            -Status 'ERROR' -Message "Windows TLS certificate check failed: $($_.Exception.Message)"
    }
}
else {
    Write-HCLog -OutputPath $OutputPath -Chapter $chapter -Section '16_01b' `
        -Status 'SKIP' -Message 'Windows checks skipped (-SkipWindowsChecks).'
}

# ── 16.2 TDE status ───────────────────────────────────────────────────────────
# Encryption state per database with TDE certificate name and expiry flags.
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     'master' `
    -SqlFile      (Join-Path $sqlDir '16_02_tde.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '16_02' `
    -SectionName  'tde' `
    -Chapter      $chapter))

# ── 16.3 AG endpoint security ─────────────────────────────────────────────────
# Database mirroring endpoint auth type, encryption algorithm, CONNECT grants,
# and certificate expiry (if certificate auth is configured).
# Returns a note row if HADR is not enabled.
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     'master' `
    -SqlFile      (Join-Path $sqlDir '16_03_ag_endpoint_security.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '16_03' `
    -SectionName  'ag_endpoint_security' `
    -Chapter      $chapter))

# ── 16.4 Certificate expiry summary ──────────────────────────────────────────
# All SQL Server internal certificates in master with expiry classification.
# Windows TLS certificates are captured in section 16_01b above.
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     'master' `
    -SqlFile      (Join-Path $sqlDir '16_04_cert_expiry_summary.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '16_04' `
    -SectionName  'cert_expiry_summary' `
    -Chapter      $chapter))

return $results
