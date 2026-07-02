# ROT-CoopSetup.ps1 - main entry point (v1 console)
# Realm of Thrones 7.1 + Bannerlord Together co-op setup / repair / loading tool.
#
# Usage:
#   .\ROT-CoopSetup.ps1              interactive menu (what most people use)
#   .\ROT-CoopSetup.ps1 -Watch       just the live loading screen
#   .\ROT-CoopSetup.ps1 -FixCrash    just run crash repair
#   .\ROT-CoopSetup.ps1 -Check       just check dependencies + install health
[CmdletBinding()]
param(
    [switch] $Watch,
    [switch] $FixCrash,
    [switch] $Check
)

$ErrorActionPreference = 'Stop'
$here   = Split-Path -Parent $MyInvocation.MyCommand.Path
$config = Join-Path (Split-Path $here -Parent) 'config\compat.json'

. "$here\Detect.ps1"
. "$here\Dependencies.ps1"
. "$here\Validate.ps1"
. "$here\LoadOrder.ps1"
. "$here\Preflight.ps1"
. "$here\FixCrash.ps1"
. "$here\ProgressReader.ps1"
. "$here\Launch.ps1"

function Show-Header {
    Write-Host ""
    Write-Host "  ===================================================" -ForegroundColor DarkCyan
    Write-Host "    REALM OF THRONES + CO-OP  -  Setup & Repair Tool" -ForegroundColor Cyan
    Write-Host "  ===================================================" -ForegroundColor DarkCyan
}

function Get-GameOrExplain {
    $g = Find-Bannerlord
    if (-not $g.Found) {
        Write-Host ""
        Write-Host "  Could not find Mount & Blade II: Bannerlord." -ForegroundColor Yellow
        Write-Host "  Make sure it's installed through Steam, then run this tool again." -ForegroundColor Gray
        Write-Host ""
        return $null
    }
    $g
}

function Show-Status($g) {
    $verOk = $g.VersionNorm -match '^1\.3\.15'
    Write-Host ""
    Write-Host "  Game folder:  $($g.Path)" -ForegroundColor Gray
    if ($verOk) { Write-Host "  Version:      $($g.Version)  (correct for co-op)" -ForegroundColor Green }
    else        { Write-Host "  Version:      $($g.Version)  -- you need 1.3.15 (Steam > right-click game > Properties > Betas)" -ForegroundColor Yellow }
    if ($g.WarSails) { Write-Host "  War Sails:    ON  -- turn it OFF for co-op (Properties > DLC)" -ForegroundColor Yellow }
    else             { Write-Host "  War Sails:    off (correct)" -ForegroundColor Green }
}

function Invoke-Menu {
    while ($true) {
        Show-Header
        $g = Get-GameOrExplain
        if (-not $g) { return }
        Show-Status $g

        Write-Host ""
        Write-Host "  What would you like to do?" -ForegroundColor White
        Write-Host ""
        Write-Host "    1) PLAY                (check, launch, and track the load)" -ForegroundColor Green
        Write-Host "    2) Ready to play?      (pre-launch check only)"
        Write-Host "    3) Check my setup      (are all mods + dependencies correct?)"
        Write-Host "    4) Fix common problems (crashes, load order, shader cache)"
        Write-Host "    5) Watch the game load (friendly loading screen)"
        Write-Host "    6) Show technical details"
        Write-Host "    Q) Quit"
        Write-Host ""
        $c = (Read-Host "  Type a number and press Enter").Trim().ToUpper()
        $prof0 = if (Test-Path $config) { Get-CompatProfile -ConfigPath $config } else { $null }

        switch ($c) {
            '1' { Start-RotCoop -Game $g -Prof $prof0 }
            '2' {
                Invoke-Preflight -Game $g -Prof $prof0 | Show-Preflight | Out-Null
                Pause-Return
            }
            '3' {
                Test-Dependencies -Game $g | Show-Dependencies
                if ($prof0) {
                    Write-Host ""
                    Write-Host "  Full install check:" -ForegroundColor Cyan
                    Format-Findings -Findings (Test-RotInstall -Game $g -Prof $prof0)
                }
                Pause-Return
            }
            '4' {
                Write-Host ""
                Write-Host "  Running repairs (a backup is made first)..." -ForegroundColor Cyan
                Repair-RotInstall -Game $g -Prof $prof0 | ForEach-Object { Write-Host "    - $_" -ForegroundColor Gray }
                Write-Host ""
                Write-Host "  Done. Try launching the game again." -ForegroundColor Green
                Pause-Return
            }
            '5' { Watch-BannerlordLoad }
            '6' { $g | Format-List; Pause-Return }
            'Q' { Write-Host ""; return }
            default { Write-Host "  Please type 1-6 or Q." -ForegroundColor Yellow; Start-Sleep 1 }
        }
    }
}

function Pause-Return {
    Write-Host ""
    Write-Host "  Press Enter to go back to the menu..." -ForegroundColor DarkGray
    $null = Read-Host
}

# --- entry ---
# Only run when this script is EXECUTED directly, not when dot-sourced/imported.
# ($MyInvocation.InvocationName is '.' when dot-sourced.)
if ($MyInvocation.InvocationName -ne '.') {
    if     ($Watch)    { Watch-BannerlordLoad }
    elseif ($FixCrash) { $g = Get-GameOrExplain; if ($g) { Repair-RotInstall -Game $g | ForEach-Object { Write-Host "  $_" } } }
    elseif ($Check)    { $g = Get-GameOrExplain; if ($g) { Test-Dependencies -Game $g | Show-Dependencies } }
    else               { Invoke-Menu }
}
