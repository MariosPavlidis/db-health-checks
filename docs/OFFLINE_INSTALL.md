# Offline installation

The offline release ZIP contains the complete, version-pinned `SqlServer` PowerShell module. The target SQL Server host does not require Internet access, PowerShell Gallery access, PackageManagement, or a NuGet provider.

The module is acquired during the trusted GitHub Actions build by using Microsoft's documented `Save-Module` method. It is not committed to the source repository.

## Install on the offline server

1. Download the release ZIP and its `.sha256` file on an Internet-connected workstation.
2. Verify the ZIP before transferring it:

```powershell
$zip = '.\db-health-checks-offline-22.2.0.zip'
$expected = (Get-Content "$zip.sha256" -Raw).Split(' ')[0].Trim()
$actual = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -ne $expected) { throw 'Release ZIP checksum mismatch.' }
```

3. Transfer the ZIP to the offline server using the approved channel and extract it.
4. Unblock the extracted files if your security policy permits it:

```powershell
Get-ChildItem 'C:\DBHealthChecks' -Recurse -File | Unblock-File
```

5. Install for the current user without elevation:

```powershell
cd C:\DBHealthChecks
.\Install-OfflineDependencies.ps1 -Scope CurrentUser
```

For all users, open Windows PowerShell as Administrator:

```powershell
.\Install-OfflineDependencies.ps1 -Scope AllUsers
```

The installer validates every packaged file against `SHA256SUMS.txt`, copies the pinned module into a PowerShell module path, imports it, and confirms that `Invoke-Sqlcmd` is available.

## Verify

Open a new PowerShell session and run:

```powershell
Get-Module SqlServer -ListAvailable |
    Sort-Object Version -Descending |
    Select-Object -First 1 Name, Version, ModuleBase

Import-Module SqlServer -ErrorAction Stop
Get-Command Invoke-Sqlcmd
```

Then execute the toolkit:

```powershell
cd C:\DBHealthChecks\MSSQL\powershell
.\orchestrator.ps1 -SqlInstance 'SERVER01'
```

## Build the offline ZIP manually

Run this only on an Internet-connected packaging workstation:

```powershell
.\tools\New-OfflinePackage.ps1
```

The module version is pinned in `dependencies/sqlserver-module.version`. Output is written to `dist` and includes the ZIP plus its SHA-256 checksum file.

## Updating the bundled module

1. Change `dependencies/sqlserver-module.version` in a pull request.
2. Run the packaging workflow.
3. Test the resulting ZIP on supported PowerShell and SQL Server versions.
4. Create a version tag only after validation.

Do not download a raw `.nupkg` and treat it as an installed module. Microsoft notes that manual NuGet downloads do not perform the same installation steps and do not include dependencies.

Official reference: https://learn.microsoft.com/powershell/sql-server/download-sql-server-ps-module
