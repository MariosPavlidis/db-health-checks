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
    [switch]$SkipWindowsChecks
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

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
        -Status 'INFO' -Message "Starting chapter: $chapterLabel"

    $chapterStart = Get-Date

    $splat = @{
        SqlInstance        = $SqlInstance
        OutputPath         = $runFolder
        SkipWindowsChecks  = $SkipWindowsChecks.IsPresent
        SqlScriptRoot      = Join-Path $PSScriptRoot '..'
    }
    if ($SqlCredential) { $splat['SqlCredential'] = $SqlCredential }

    $chapterResult = [PSCustomObject]@{
        Chapter        = $chapterLabel
        Status         = 'OK'
        SectionsRun    = 0
        SectionsOK     = 0
        SectionsFailed = 0
        DurationSec    = 0
        Error          = ''
    }

    try {
        $sectionResults = & $script.FullName @splat
        $arr = @($sectionResults)
        $chapterResult.SectionsRun    = $arr.Count
        $chapterResult.SectionsOK     = @($arr | Where-Object { $_.Status -eq 'OK' }).Count
        $chapterResult.SectionsFailed = @($arr | Where-Object { $_.Status -eq 'ERROR' }).Count
        if ($chapterResult.SectionsFailed -gt 0) { $chapterResult.Status = 'PARTIAL' }
    }
    catch {
        $chapterResult.Status = 'ERROR'
        $chapterResult.Error  = $_.Exception.Message
        Write-HCLog -OutputPath $runFolder -Chapter $chapterLabel -Section '' `
            -Status 'ERROR' -Message "Chapter failed: $($_.Exception.Message)"
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

$totalOK     = @($summary | Where-Object { $_.Status -eq 'OK'      }).Count
$totalPartial= @($summary | Where-Object { $_.Status -eq 'PARTIAL'  }).Count
$totalFailed = @($summary | Where-Object { $_.Status -eq 'ERROR'    }).Count

Write-HCLog -OutputPath $runFolder -Chapter 'ORCHESTRATOR' -Section '' `
    -Status 'INFO' -Message "Health check complete. Chapters: OK=$totalOK  PARTIAL=$totalPartial  FAILED=$totalFailed"
Write-HCLog -OutputPath $runFolder -Chapter 'ORCHESTRATOR' -Section '' `
    -Status 'INFO' -Message "Output folder: $runFolder"
Write-HCLog -OutputPath $runFolder -Chapter 'ORCHESTRATOR' -Section '' `
    -Status 'INFO' -Message "Summary: $summaryPath"

Write-Host "`nHealth check complete. Results in: $runFolder" -ForegroundColor Cyan
