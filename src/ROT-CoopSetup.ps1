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

. "$here\Common.ps1"
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
. "$here\CrashReport.ps1"

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
        Write-Host "  Could not find Mount & Blade II: Bannerlord on this PC." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  I checked: Steam (every library folder), GOG, Epic, and Xbox/Game Pass." -ForegroundColor Gray
        Write-Host "  If the game IS installed somewhere unusual, paste its folder below and" -ForegroundColor Gray
        Write-Host "  I'll remember it - it's the folder that contains 'bin' and 'Modules'," -ForegroundColor Gray
        Write-Host "  e.g.  D:\Games\Mount & Blade II Bannerlord" -ForegroundColor DarkGray
        Write-Host ""
        $p = (Read-Host "  Game folder (or just press Enter to close)").Trim('"',' ')
        if (-not $p) { return $null }
        if (Test-BannerlordRoot $p) {
            Save-ToolSetting -Name 'gamePath' -Value $p
            Write-Host ""
            Write-Host "  Found it - saved for next time." -ForegroundColor Green
            return (Find-Bannerlord)
        }
        Write-Host ""
        Write-Host "  That folder doesn't look like a Bannerlord install (no bin\ + Modules\ inside)." -ForegroundColor Red
        Write-Host "  Double-check the path and run the tool again." -ForegroundColor Gray
        Write-Host ""
        Write-Host "  Press Enter to close..." -ForegroundColor DarkGray
        $null = Read-Host
        return $null
    }
    $g
}

function Show-Status($g, $prof) {
    $verOk = $g.VersionNorm -match '^1\.3\.15'
    Write-Host ""
    Write-Host "  Game folder:  $($g.Path)$(if ($g.Platform) { "  [$($g.Platform)]" })" -ForegroundColor Gray
    if ($verOk) { Write-Host "  Version:      $($g.Version)  (correct for co-op)" -ForegroundColor Green }
    else        { Write-Host "  Version:      $($g.Version)  -- you need 1.3.15: $(Get-VersionFixAdvice $g '1.3.15')" -ForegroundColor Yellow }
    if ($g.WarSailsEnabled) { Write-Host "  War Sails:    ENABLED  -- turn it OFF for co-op (launcher Mods tab / Properties > DLC)" -ForegroundColor Yellow }
    elseif ($g.WarSails)    { Write-Host "  War Sails:    installed but off (fine)" -ForegroundColor Green }
    else                    { Write-Host "  War Sails:    off (correct)" -ForegroundColor Green }
    # ROT build - THE line that would have caught the ROT-8.0-without-DLC crash at a glance
    $wantRot = '7.1'
    if ($prof -and $prof.mods.ROT.version) { $wantRot = [string]$prof.mods.ROT.version }
    if ($g.RotVersion) {
        $ed = Get-RotEdition -ModulesPath $g.ModulesPath -WantVersion $wantRot
        $rotLabel = if ($ed.GameStamped) { "non-Warsails (v$($ed.Version) = game-version stamp; edition read from ROT.dll)" } else { "v$($ed.Version)" }
        if ($ed.Match)                        { Write-Host "  ROT:          $rotLabel  (correct build)" -ForegroundColor Green }
        elseif ($ed.Edition -eq 'warsails')   { Write-Host "  ROT:          $rotLabel  -- WARSAILS build! This setup needs ROT $wantRot (non-Warsails)" -ForegroundColor Red }
        else                                  { Write-Host "  ROT:          $rotLabel  -- expected $wantRot" -ForegroundColor Yellow }
    } else { Write-Host "  ROT:          not installed yet" -ForegroundColor Yellow }
}

# Quick health scan -> tell the user the ONE thing to do next, in plain English.
# Removes the "which option do I even pick?" problem for non-technical users.
function Show-Recommendation($g, $prof) {
    $mods = $g.ModulesPath
    # cheap checks (no heavy work)
    $verOk   = $g.VersionNorm -match '^1\.3\.15'
    $blse    = Test-Path (Join-Path $g.BinPath 'Bannerlord.BLSE.LauncherEx.exe')
    $rotCount= @(Get-RotModuleNames | Where-Object { Test-Path (Join-Path $mods "$_\SubModule.xml") }).Count
    $stub    = @(Get-StubDeps -ModulesPath $mods).Count -gt 0
    $mcm     = Test-Path (Join-Path $mods 'Bannerlord.MBOptionScreen\bin\Win64_Shipping_Client\MCMv5.dll')

    Write-Host ""
    if (-not $verOk) {
        Write-Host "  >> START HERE: your game isn't on 1.3.15." -ForegroundColor Yellow
        Write-Host "     Fix: $(Get-VersionFixAdvice $g '1.3.15'). Then come back." -ForegroundColor Yellow
    }
    elseif ($rotCount -lt 3) {
        Write-Host "  >> START HERE: Realm of Thrones isn't installed yet ($rotCount/4 modules found)." -ForegroundColor Yellow
        Write-Host "     Install ROT 7.1 into your Modules folder, then pick option 3 to check it." -ForegroundColor Yellow
    }
    elseif ($g.RotVersion -and -not (Get-RotEdition -ModulesPath $mods -WantVersion $(if ($prof -and $prof.mods.ROT.version) { [string]$prof.mods.ROT.version } else { '7.1' })).Match) {
        $wantRot = if ($prof -and $prof.mods.ROT.version) { [string]$prof.mods.ROT.version } else { '7.1' }
        $edn = Get-RotEdition -ModulesPath $mods -WantVersion $wantRot
        Write-Host "  >> START HERE: you installed ROT v$($edn.Version) - the WRONG build for this setup." -ForegroundColor Yellow
        if ($edn.Edition -eq 'warsails') {
            Write-Host "     That's the Warsails edition: without the War Sails DLC it crashes before the" -ForegroundColor Yellow
            Write-Host "     menu even appears, and it can't co-op with a $wantRot host either way." -ForegroundColor Yellow
        }
        Write-Host "     Install ROT $wantRot (the 'ROT $wantRot for Bannerlord 1.3.15' file), then option 3 to re-check." -ForegroundColor Yellow
    }
    elseif (-not $blse) {
        Write-Host "  >> START HERE: BLSE (the launcher ROT needs) isn't installed. Pick option 4" -ForegroundColor Yellow
        Write-Host "     (FIX my dependencies) - it downloads and installs BLSE for you." -ForegroundColor Yellow
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
    # Pick a profile ONCE per run. compat.json currently ships one stack, but the day a
    # second verified combo lands (new ROT / new game version), users just pick from a
    # list - no tool changes needed.
    $activeProfileId = $null
    if (Test-Path $config) {
        $allProfiles = @((Get-Content $config -Raw | ConvertFrom-Json).profiles)
        if ($allProfiles.Count -gt 1) {
            Show-Header
            Write-Host ""
            Write-Host "  This tool knows more than one verified mod stack:" -ForegroundColor Cyan
            for ($i = 0; $i -lt $allProfiles.Count; $i++) { Write-Host "    $($i+1)) $($allProfiles[$i].name)" }
            Write-Host ""
            $pick = (Read-Host "  Which one are you setting up? (Enter = 1)").Trim()
            $idx = if ($pick -match '^\d+$' -and [int]$pick -ge 1 -and [int]$pick -le $allProfiles.Count) { [int]$pick - 1 } else { 0 }
            $activeProfileId = $allProfiles[$idx].id
        } elseif ($allProfiles.Count -eq 1) {
            $activeProfileId = $allProfiles[0].id
        }
    }

    while ($true) {
        Show-Header
        $g = Get-GameOrExplain
        if (-not $g) { return }
        $prof0 = if ($activeProfileId) { Get-CompatProfile -ConfigPath $config -ProfileId $activeProfileId } else { $null }
        Show-Status $g $prof0
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
        Write-Host "   10) Read a crash report  (the .zip BLSE offers to save when the game dies)"
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
                Write-Host "  This downloads the OFFICIAL Harmony, ButterLib, UIExtenderEx, MCM and" -ForegroundColor Gray
                Write-Host "  BLSE (the correct versions for ROT), and replaces any wrong 'stub' copies." -ForegroundColor Gray
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
            '10' {
                Write-Host ""
                Write-Host "  When Bannerlord crashes through BLSE, it shows a dialog with a 'Save report'" -ForegroundColor Gray
                Write-Host "  button. This reads that report (yours or a friend's) and explains the crash." -ForegroundColor Gray
                Write-Host ""
                $cp = (Read-Host "  Drag the crash report .zip here (or paste its path)").Trim('"',' ')
                $rep = Read-CrashReport -Path $cp
                if ($rep) { Show-CrashDiagnosis -Report $rep }
                Pause-Return
            }
            'Q' { Write-Host ""; return }
            default { Write-Host "  Please type 1-10 or Q." -ForegroundColor Yellow; Start-Sleep 1 }
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
