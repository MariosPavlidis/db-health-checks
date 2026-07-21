# =============================================================================
# 15_security_access.ps1 — Chapter 15: Security and Access
# Checklist sections: 15.1 – 15.6
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
$chapter  = '15_security_access'
$sqlDir   = Join-Path $SqlScriptRoot "sql\15_security_access"

. (Join-Path $PSScriptRoot 'shared\HC-Helpers.ps1')

$results  = [System.Collections.Generic.List[PSCustomObject]]::new()
$sqlSplat = @{ SqlInstance = $SqlInstance }
if ($SqlCredential) { $sqlSplat['SqlCredential'] = $SqlCredential }

# ── 15.1 Server principals (logins) ──────────────────────────────────────────
# Enumerates all server-level logins with flags for disabled, SQL auth,
# possible personal accounts, and invalid default database.
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     'master' `
    -SqlFile      (Join-Path $sqlDir '15_01_server_principals.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '15_01' `
    -SectionName  'server_principals' `
    -Chapter      $chapter))

# ── 15.2 Server roles and explicit permissions ────────────────────────────────
# Fixed server role membership plus explicit server-level GRANT/DENY.
# Flags disabled members, possible personal accounts, and high-privilege grants.
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     'master' `
    -SqlFile      (Join-Path $sqlDir '15_02_server_roles.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '15_02' `
    -SectionName  'server_roles' `
    -Chapter      $chapter))

# ── 15.3 Database users and permissions ──────────────────────────────────────
# Cursor across all ONLINE user databases collecting users, role membership,
# orphaned users, guest status, and db_owner membership.
# Runs against master (script uses dynamic SQL internally via EXEC sp_executesql).
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     'master' `
    -SqlFile      (Join-Path $sqlDir '15_03_db_users_permissions.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '15_03' `
    -SectionName  'db_users_permissions' `
    -Chapter      $chapter `
    -QueryTimeout 600))

# ── 15.4 Database security settings ──────────────────────────────────────────
# Per-database TRUSTWORTHY, cross-db chaining, containment, CLR assembly
# permission sets, CLR strict security (SQL 2017+), and database owner.
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     'master' `
    -SqlFile      (Join-Path $sqlDir '15_04_security_db_settings.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '15_04' `
    -SectionName  'security_db_settings' `
    -Chapter      $chapter))

# ── 15.5 SA account and sysadmin role membership ─────────────────────────────
# SA account status (original and renamed), built-in Windows accounts,
# and full sysadmin role membership list for emergency access review.
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     'master' `
    -SqlFile      (Join-Path $sqlDir '15_05_sa_privileged.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '15_05' `
    -SectionName  'sa_privileged' `
    -Chapter      $chapter))

# ── 15.6 Linked servers and credentials ──────────────────────────────────────
# Linked server definitions with security login mappings (flags public mappings)
# and SQL Server credential objects.
$results.Add((Invoke-HCSection @sqlSplat `
    -Database     'master' `
    -SqlFile      (Join-Path $sqlDir '15_06_linked_servers.sql') `
    -OutputPath   $OutputPath `
    -SectionId    '15_06' `
    -SectionName  'linked_servers' `
    -Chapter      $chapter))

return $results
