# =============================================================================
# orchestrator.ps1 — SQL Server Health Check Orchestrator
# =============================================================================
# Usage:
#   .\orchestrator.ps1 -SqlInstance "SERVER01"
#   .\orchestrator.ps1 -SqlInstance "SERVER01\INST" -Chapters @("03","13","17")
#   .\orchestrator.ps1 -SqlInstance "SERVER01" -SqlCredential (Get-Credential) -SkipWindowsChecks
# =============================================================================

[CmdletBinding()]
param(
    # SQL Server instance name (required)
    [Parameter(Mandatory)]
    [string]$SqlInstance,

    # Root output folder. A timestamped subfolder is created automatically.
    [string]$OutputPath = '.\output',

    # Chapters to run. Use "all" or specify chapter numbers e.g. @("01","03","13").
    [string[]]$Chapters = @('all'),

    # Optional SQL Authentication credential. If omitted, Windows Auth is used.
    [System.Management.Automation.PSCredential]$SqlCredential,

    # Skip all Windows-native checks (WMI, event logs, cluster, registry).
    # Use when running remotely without WinRM/CIM access to the target host.
    [switch]$SkipWindowsChecks,

    # Maximum seconds a chapter is allowed to run before it is killed and logged as TIMEOUT.
    # Also controls the per-query SQL timeout inside Invoke-HCSql/Invoke-HCSection.
    [int]$ChapterTimeoutSec = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$SqlInstance = $SqlInstance.Trim()

# ── Module check ──────────────────────────────────────────────────────────────
$helperPath = Join-Path $PSScriptRoot 'shared\HC-Helpers.ps1'
if (-not (Test-Path $helperPath)) {
    throw "HC-Helpers.ps1 not found at: $helperPath"
}
. $helperPath
Ensure-HCSqlModule

# ── Create timestamped output folder ──────────────────────────────────────────
$safeInstance = $SqlInstance -replace '[\\/:*?"<>|]', '_'
$timestamp    = (Get-Date).ToString('yyyyMMdd_HHmmss')
$runFolder    = Join-Path $OutputPath "${timestamp}_${safeInstance}"

if (-not (Test-Path $runFolder)) {
    New-Item -ItemType Directory -Path $runFolder -Force | Out-Null
}

Write-HCLog -OutputPath $runFolder -Chapter 'ORCHESTRATOR' -Section '' `
    -Status 'INFO' -Message "Health check started. Instance: $SqlInstance  Output: $runFolder"

# ── Validate SQL Server connectivity before running anything ──────────────────
Write-HCLog -OutputPath $runFolder -Chapter 'ORCHESTRATOR' -Section '' `
    -Status 'INFO' -Message "Testing connectivity to $SqlInstance ..."

try {
    $connSplat = @{
        ServerInstance         = $SqlInstance
        Query                  = "SELECT @@SERVERNAME AS [ServerName], @@VERSION AS [Version];"
        QueryTimeout           = 15
        TrustServerCertificate = $true
        ErrorAction            = 'Stop'
    }
    if ($SqlCredential) {
        $connSplat['Username'] = $SqlCredential.UserName
        $connSplat['Password'] = $SqlCredential.GetNetworkCredential().Password
    }
    $connTest = Invoke-Sqlcmd @connSplat
    Write-HCLog -OutputPath $runFolder -Chapter 'ORCHESTRATOR' -Section '' `
        -Status 'OK' -Message "Connected: $($connTest.ServerName)"
}
catch {
    $errMsg = $_.Exception.Message
    Write-HCLog -OutputPath $runFolder -Chapter 'ORCHESTRATOR' -Section '' `
        -Status 'ERROR' -Message "Cannot connect to '$SqlInstance': $errMsg"
    Write-Host "`nERROR: Cannot connect to '$SqlInstance'" -ForegroundColor Red
    Write-Host $errMsg -ForegroundColor Red
    Write-Host "No chapters were run." -ForegroundColor Yellow
    return
}

# ── Discover chapter scripts ──────────────────────────────────────────────────
$chapterScripts = @(Get-ChildItem -Path $PSScriptRoot -Filter '*.ps1' |
    Where-Object { $_.Name -match '^\d{2}_' } |
    Sort-Object Name)

if ($Chapters -notcontains 'all') {
    $chapterScripts = @($chapterScripts | Where-Object {
        $num = $_.BaseName.Substring(0, 2)
        $Chapters -contains $num
    })
}

if ($chapterScripts.Count -eq 0) {
    Write-HCLog -OutputPath $runFolder -Chapter 'ORCHESTRATOR' -Section '' `
        -Status 'WARN' -Message 'No chapter scripts matched the Chapters filter. Exiting.'
    return
}

Write-HCLog -OutputPath $runFolder -Chapter 'ORCHESTRATOR' -Section '' `
    -Status 'INFO' -Message "Running $($chapterScripts.Count) chapter script(s)."

# ── Chapter execution loop ────────────────────────────────────────────────────
$summary = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($script in $chapterScripts) {
    $chapterLabel = $script.BaseName
    Write-HCLog -OutputPath $runFolder -Chapter $chapterLabel -Section '' `
        -Status 'INFO' -Message "Starting chapter: $chapterLabel (timeout: ${ChapterTimeoutSec}s)"

    $chapterStart = Get-Date

    $chapterResult = [PSCustomObject]@{
        Chapter        = $chapterLabel
        Status         = 'OK'
        SectionsRun    = 0
        SectionsOK     = 0
        SectionsFailed = 0
        DurationSec    = 0
        Error          = ''
    }

    # ── Run chapter in a PowerShell runspace (thread in this process) ────────
    # Runspaces share the parent process so module DLLs are already in memory —
    # startup is near-instant vs. Start-Job which spawns a new process and must
    # reload every module from disk per chapter.
    $scriptFullPath   = $script.FullName
    $jobSqlScriptRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $jobRunFolder     = (Resolve-Path $runFolder).Path

    $ps = [System.Management.Automation.PowerShell]::Create()
    [void]$ps.AddScript({
        param($scriptPath, $sqlInst, $outPath, $skipWin, $sqlRoot, $cred)
        $params = @{
            SqlInstance       = $sqlInst
            OutputPath        = $outPath
            SkipWindowsChecks = $skipWin
            SqlScriptRoot     = $sqlRoot
        }
        if ($cred) { $params['SqlCredential'] = $cred }
        & $scriptPath @params
    })
    [void]$ps.AddParameter('scriptPath', $scriptFullPath)
    [void]$ps.AddParameter('sqlInst',    $SqlInstance)
    [void]$ps.AddParameter('outPath',    $jobRunFolder)
    [void]$ps.AddParameter('skipWin',    $SkipWindowsChecks.IsPresent)
    [void]$ps.AddParameter('sqlRoot',    $jobSqlScriptRoot)
    [void]$ps.AddParameter('cred',       $SqlCredential)   # passed directly — no temp file needed

    $asyncResult = $ps.BeginInvoke()
    $completed   = $asyncResult.AsyncWaitHandle.WaitOne(
                       [TimeSpan]::FromSeconds($ChapterTimeoutSec))

    if (-not $completed) {
        $ps.Stop()
        $ps.Dispose()

        $chapterResult.Status = 'TIMEOUT'
        $chapterResult.Error  = "Chapter exceeded ${ChapterTimeoutSec}s timeout - killed."
        Write-HCLog -OutputPath $runFolder -Chapter $chapterLabel -Section '' `
            -Status 'TIMEOUT' -Message $chapterResult.Error
    }
    else {
        try {
            $sectionResults = $ps.EndInvoke($asyncResult)
            $ps.Dispose()

            $arr = @($sectionResults)
            $chapterResult.SectionsRun    = $arr.Count
            $chapterResult.SectionsOK     = @($arr | Where-Object { $_.Status -eq 'OK'    }).Count
            $chapterResult.SectionsFailed = @($arr | Where-Object { $_.Status -eq 'ERROR' }).Count
            if ($chapterResult.SectionsFailed -gt 0) { $chapterResult.Status = 'PARTIAL' }
        }
        catch {
            $ps.Dispose()

            $chapterResult.Status = 'ERROR'
            $chapterResult.Error  = $_.Exception.Message
            Write-HCLog -OutputPath $runFolder -Chapter $chapterLabel -Section '' `
                -Status 'ERROR' -Message "Chapter failed: $($_.Exception.Message)"
        }
    }

    $chapterResult.DurationSec = [math]::Round(((Get-Date) - $chapterStart).TotalSeconds, 1)
    $summary.Add($chapterResult)

    Write-HCLog -OutputPath $runFolder -Chapter $chapterLabel -Section '' `
        -Status $chapterResult.Status `
        -Message "Completed in $($chapterResult.DurationSec)s - OK:$($chapterResult.SectionsOK) FAILED:$($chapterResult.SectionsFailed)"
}

# ── Write summary CSV ─────────────────────────────────────────────────────────
$summaryPath = Join-Path $runFolder 'hc_summary.csv'
$summary | Export-Csv -Path $summaryPath -NoTypeInformation -Encoding UTF8

$totalOK      = @($summary | Where-Object { $_.Status -eq 'OK'      }).Count
$totalPartial = @($summary | Where-Object { $_.Status -eq 'PARTIAL'  }).Count
$totalFailed  = @($summary | Where-Object { $_.Status -eq 'ERROR'    }).Count
$totalTimeout = @($summary | Where-Object { $_.Status -eq 'TIMEOUT'  }).Count

Write-HCLog -OutputPath $runFolder -Chapter 'ORCHESTRATOR' -Section '' `
    -Status 'INFO' -Message "Health check complete. Chapters: OK=$totalOK  PARTIAL=$totalPartial  FAILED=$totalFailed  TIMEOUT=$totalTimeout"
Write-HCLog -OutputPath $runFolder -Chapter 'ORCHESTRATOR' -Section '' `
    -Status 'INFO' -Message "Output folder: $runFolder"
Write-HCLog -OutputPath $runFolder -Chapter 'ORCHESTRATOR' -Section '' `
    -Status 'INFO' -Message "Summary: $summaryPath"

Write-Host "`nHealth check complete. Results in: $runFolder" -ForegroundColor Cyan
