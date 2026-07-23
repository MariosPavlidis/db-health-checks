#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('CurrentUser','AllUsers')]
    [string]$Scope = 'CurrentUser',
    [switch]$SkipHashValidation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$packageRoot = $PSScriptRoot
$version = (Get-Content -LiteralPath (Join-Path $packageRoot 'sqlserver-module.version') -Raw).Trim()
$sourceModule = Join-Path $packageRoot "dependencies\Modules\SqlServer\$version"
$manifestPath = Join-Path $packageRoot 'SHA256SUMS.txt'

if (-not (Test-Path -LiteralPath (Join-Path $sourceModule 'SqlServer.psd1'))) {
    throw "Bundled SqlServer $version module was not found at $sourceModule"
}

if (-not $SkipHashValidation) {
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw 'SHA256SUMS.txt is missing. Refusing installation without -SkipHashValidation.'
    }

    foreach ($line in Get-Content -LiteralPath $manifestPath) {
        if ($line -notmatch '^([0-9a-fA-F]{64})  (.+)$') {
            throw "Invalid checksum entry: $line"
        }
        $expected = $Matches[1].ToLowerInvariant()
        $relative = $Matches[2].Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        $target = Join-Path $packageRoot $relative
        if (-not (Test-Path -LiteralPath $target)) { throw "Package file missing: $relative" }
        $actual = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $expected) { throw "Checksum mismatch: $relative" }
    }
}

if ($Scope -eq 'AllUsers') {
    $moduleBase = Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules\SqlServer'
    $identity = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $identity.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'AllUsers installation requires an elevated PowerShell session.'
    }
}
else {
    $documents = [Environment]::GetFolderPath('MyDocuments')
    $moduleBase = Join-Path $documents 'WindowsPowerShell\Modules\SqlServer'
}

$destination = Join-Path $moduleBase $version
if ($PSCmdlet.ShouldProcess($destination, "Install bundled SqlServer module $version")) {
    New-Item -ItemType Directory -Path $moduleBase -Force | Out-Null
    if (Test-Path -LiteralPath $destination) {
        Remove-Item -LiteralPath $destination -Recurse -Force
    }
    Copy-Item -LiteralPath $sourceModule -Destination $destination -Recurse -Force

    Import-Module (Join-Path $destination 'SqlServer.psd1') -Force -ErrorAction Stop
    $module = Get-Module SqlServer
    $invokeSqlCmd = Get-Command Invoke-Sqlcmd -ErrorAction Stop

    [PSCustomObject]@{
        Module        = $module.Name
        Version       = $module.Version.ToString()
        InstallPath   = $destination
        InvokeSqlcmd  = $invokeSqlCmd.Source
        HashValidated = (-not $SkipHashValidation)
    }
}
