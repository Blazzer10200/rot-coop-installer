# ROT-CoopSetup.ps1 - main entry point (v1 console)
# Realm of Thrones 7.1 + Bannerlord Together co-op setup / repair / loading tool.
#
# Usage:
#   .\ROT-CoopSetup.ps1              interactive menu (what most people use)
#   .\ROT-CoopSetup.ps1 -Watch       just the live loading screen
#   .\ROT-CoopSetup.ps1 -FixCrash    just run crash repair
#   .\ROT-CoopSetup.ps1 -FixDeps     just download + install the correct dependencies
#   .\ROT-CoopSetup.ps1 -Check       just check dependencies + install health
[CmdletBinding()]
param(
    [switch] $Watch,
    [switch] $FixCrash,
    [switch] $FixDeps,
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
. "$here\FixDependencies.ps1"
. "$here\ProgressReader.ps1"
. "$here\Launch.ps1"
. "$here\CoopSync.ps1"

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

# Quick health scan -> tell the user the ONE thing to do next, in plain English.
# Removes the "which option do I even pick?" problem for non-technical users.
function Show-Recommendation($g, $prof) {
    $mods = $g.ModulesPath
    # cheap checks (no heavy work)
    $verOk   = $g.VersionNorm -match '^1\.3\.15'
    $blse    = Test-Path (Join-Path $g.BinPath 'Bannerlord.BLSE.LauncherEx.exe')
    $rotCount= @('ROT-Core','ROT-Content','ROT_Map','ROT-Dragon') | Where-Object { Test-Path (Join-Path $mods "$_\SubModule.xml") } | Measure-Object | ForEach-Object Count
    $stub    = $false
    foreach ($d in 'Bannerlord.Harmony','Bannerlord.ButterLib','Bannerlord.UIExtenderEx','Bannerlord.MBOptionScreen') {
        $b = Join-Path $mods "$d\bin\Win64_Shipping_Client"
        if ((Test-Path (Join-Path $b 'BetaDeps.Foundation.dll')) -or (Test-Path (Join-Path $b 'BetaDeps.Harmony.dll'))) { $stub = $true }
    }
    $mcm = Test-Path (Join-Path $mods 'Bannerlord.MBOptionScreen\bin\Win64_Shipping_Client\MCMv5.dll')

    Write-Host ""
    if (-not $verOk) {
        Write-Host "  >> START HERE: your game isn't on 1.3.15. In Steam, right-click the game >" -ForegroundColor Yellow
        Write-Host "     Properties > Betas > pick 1.3.15. Then come back." -ForegroundColor Yellow
    }
    elseif ($rotCount -lt 3) {
        Write-Host "  >> START HERE: Realm of Thrones isn't installed yet ($rotCount/4 modules found)." -ForegroundColor Yellow
        Write-Host "     Install ROT 7.1 into your Modules folder, then pick option 3 to check it." -ForegroundColor Yellow
    }
    elseif (-not $blse) {
        Write-Host "  >> START HERE: BLSE (the launcher ROT needs) isn't installed. Pick option 3" -ForegroundColor Yellow
        Write-Host "     for the download link, install it, then come back." -ForegroundColor Yellow
    }
    elseif ($stub -or -not $mcm) {
        Write-Host "  >> RECOMMENDED: your dependencies look wrong -" -ForegroundColor Yellow
        if ($stub)     { Write-Host "     - you have 'stub' dependency copies (these cause the endless-loading loop)" -ForegroundColor Yellow }
        if (-not $mcm) { Write-Host "     - MCM is missing (ROT crashes ~26s into a new game without it)" -ForegroundColor Yellow }
        Write-Host "     Fix it automatically: close the game, then pick option 4 (FIX my dependencies)." -ForegroundColor Green
    }
    else {
        Write-Host "  >> Looks good! Your setup seems correct. Pick option 1 to PLAY," -ForegroundColor Green
        Write-Host "     or option 6 if you want to know how to start a co-op game." -ForegroundColor Green
    }
}

function Invoke-Menu {
    while ($true) {
        Show-Header
        $g = Get-GameOrExplain
        if (-not $g) { return }
        Show-Status $g
        $prof0 = if (Test-Path $config) { Get-CompatProfile -ConfigPath $config } else { $null }
        Show-Recommendation $g $prof0

        Write-Host ""
        Write-Host "  What would you like to do?" -ForegroundColor White
        Write-Host ""
        Write-Host "   PLAY" -ForegroundColor DarkGray
        Write-Host "    1) PLAY  -  check, launch, and track the load" -ForegroundColor Green
        Write-Host "    2) Am I ready to play?  (pre-launch check)"
        Write-Host ""
        Write-Host "   FIX / SET UP" -ForegroundColor DarkGray
        Write-Host "    3) Check my setup  (what's installed, what's wrong)"
        Write-Host "    4) FIX my dependencies  -  download + install the correct ones" -ForegroundColor Green
        Write-Host "    5) Fix common problems  (crashes, load order, shader cache, bad files)"
        Write-Host ""
        Write-Host "   CO-OP" -ForegroundColor DarkGray
        Write-Host "    6) How do I start / join a co-op game?" -ForegroundColor Green
        Write-Host "    7) Match my setup with a friend  (export / compare)"
        Write-Host ""
        Write-Host "   OTHER" -ForegroundColor DarkGray
        Write-Host "    8) Watch the game load  (friendly loading screen)"
        Write-Host "    9) Show technical details"
        Write-Host "    Q) Quit"
        Write-Host ""
        $c = (Read-Host "  Type a number and press Enter").Trim().ToUpper()
        # $prof0 already loaded above (before the recommendation scan)

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
                Write-Host "  FIX DEPENDENCIES" -ForegroundColor Cyan
                Write-Host "  This downloads the OFFICIAL Harmony, ButterLib, UIExtenderEx and MCM" -ForegroundColor Gray
                Write-Host "  (the correct versions for ROT), and replaces any wrong 'stub' copies." -ForegroundColor Gray
                Write-Host "  This is the #1 fix for the game looping forever on a new campaign." -ForegroundColor Gray
                Write-Host ""
                Write-Host "  Requirements: the game must be CLOSED, and you need an internet connection." -ForegroundColor DarkGray
                Write-Host "  (Anything replaced is backed up first.)" -ForegroundColor DarkGray
                Write-Host ""
                $ok = (Read-Host "  Download and install the correct dependencies now? (y/n)").Trim().ToUpper()
                if ($ok -eq 'Y') {
                    Write-Host ""
                    Write-Host "  Working... (downloading a few small files, please wait)" -ForegroundColor Cyan
                    Repair-Dependencies -Game $g | ForEach-Object { Write-Host "    - $_" -ForegroundColor Gray }
                    Write-Host ""
                    Write-Host "  Tip: now run option 5 to reset the load order, then option 1 to play." -ForegroundColor Green
                } else { Write-Host "  Skipped." -ForegroundColor Yellow }
                Pause-Return
            }
            '5' {
                Write-Host ""
                Write-Host "  Running repairs (a backup is made first)..." -ForegroundColor Cyan
                Repair-RotInstall -Game $g -Prof $prof0 | ForEach-Object { Write-Host "    - $_" -ForegroundColor Gray }
                Write-Host ""
                Write-Host "  Done. Try launching the game again." -ForegroundColor Green
                Pause-Return
            }
            '6' { Show-CoopHowTo; Pause-Return }
            '7' {
                Write-Host ""
                Write-Host "  Co-op setup matching:" -ForegroundColor Cyan
                Write-Host "    A) I'm the HOST - export my setup to share"
                Write-Host "    B) Compare my setup to a friend's file"
                Write-Host ""
                $sub = (Read-Host "  Choose A or B").Trim().ToUpper()
                if ($sub -eq 'A') { Export-CoopProfile -Game $g | Out-Null }
                elseif ($sub -eq 'B') {
                    $ff = (Read-Host "  Drag your friend's file here (or paste its path)").Trim('"',' ')
                    Compare-CoopProfile -Game $g -FriendFile $ff
                }
                Pause-Return
            }
            '8' { Watch-BannerlordLoad }
            '9' { $g | Format-List; Pause-Return }
            'Q' { Write-Host ""; return }
            default { Write-Host "  Please type 1-9 or Q." -ForegroundColor Yellow; Start-Sleep 1 }
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
    elseif ($FixDeps)  { $g = Get-GameOrExplain; if ($g) { Repair-Dependencies -Game $g | ForEach-Object { Write-Host "  $_" } } }
    elseif ($Check)    { $g = Get-GameOrExplain; if ($g) { Test-Dependencies -Game $g | Show-Dependencies } }
    else               { Invoke-Menu }
}
