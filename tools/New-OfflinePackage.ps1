#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$SourceRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$OutputDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'dist'),
    [string]$ModuleVersion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$versionFile = Join-Path $SourceRoot 'dependencies\sqlserver-module.version'
if (-not $ModuleVersion) {
    $ModuleVersion = (Get-Content -LiteralPath $versionFile -Raw).Trim()
}
if ($ModuleVersion -notmatch '^\d+\.\d+\.\d+$') {
    throw "Invalid SqlServer module version: $ModuleVersion"
}

$packageName = "db-health-checks-offline-$ModuleVersion"
$stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
$packageRoot = Join-Path $stagingRoot $packageName
$moduleRoot  = Join-Path $packageRoot 'dependencies\Modules'

try {
    New-Item -ItemType Directory -Path $packageRoot, $moduleRoot, $OutputDirectory -Force | Out-Null

    Save-Module -Name SqlServer -RequiredVersion $ModuleVersion -Repository PSGallery -Path $moduleRoot -Force

    $savedManifest = Join-Path $moduleRoot "SqlServer\$ModuleVersion\SqlServer.psd1"
    if (-not (Test-Path -LiteralPath $savedManifest)) {
        throw "SqlServer $ModuleVersion was not downloaded to the expected path."
    }

    Copy-Item -LiteralPath (Join-Path $SourceRoot 'MSSQL') -Destination $packageRoot -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $SourceRoot 'offline\Install-OfflineDependencies.ps1') -Destination $packageRoot -Force
    Copy-Item -LiteralPath (Join-Path $SourceRoot 'docs\OFFLINE_INSTALL.md') -Destination $packageRoot -Force
    Copy-Item -LiteralPath (Join-Path $SourceRoot 'README.md') -Destination $packageRoot -Force
    Copy-Item -LiteralPath $versionFile -Destination $packageRoot -Force

    $manifestPath = Join-Path $packageRoot 'SHA256SUMS.txt'
    Get-ChildItem -LiteralPath $packageRoot -File -Recurse |
        Where-Object { $_.FullName -ne $manifestPath } |
        Sort-Object FullName |
        ForEach-Object {
            $relativePath = $_.FullName.Substring($packageRoot.Length + 1).Replace('\','/')
            $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            "$hash  $relativePath"
        } | Set-Content -LiteralPath $manifestPath -Encoding ASCII

    $zipPath = Join-Path $OutputDirectory "$packageName.zip"
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    Compress-Archive -Path (Join-Path $packageRoot '*') -DestinationPath $zipPath -CompressionLevel Optimal

    $zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    "$zipHash  $([System.IO.Path]::GetFileName($zipPath))" |
        Set-Content -LiteralPath "$zipPath.sha256" -Encoding ASCII

    Get-Item -LiteralPath $zipPath
}
finally {
    if (Test-Path -LiteralPath $stagingRoot) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force
    }
}
