# Dependencies.ps1 - deep dependency detection + guided fix.
#
# A Bannerlord dependency is only REALLY installed when ALL of these are true:
#   1. The module folder exists in \Modules\
#   2. Its SubModule.xml is present and parseable
#   3. Its key DLL exists in bin\Win64_Shipping_Client\  (folder alone is NOT enough)
#   4. Its version satisfies what the profile needs
# This module checks all four and tells the user - in plain English - exactly what to do.

# Canonical dependency spec. keyDll = the file that proves the code actually shipped.
function Get-DependencySpec {
    @(
        @{ Name='Harmony';       Module='Bannerlord.Harmony';       KeyDll='Bannerlord.Harmony.dll';       Extra='0Harmony.dll';        Why='Core patching library. Nothing loads without it.';        Nexus='https://www.nexusmods.com/mountandblade2bannerlord/mods/2006' }
        @{ Name='UIExtenderEx';  Module='Bannerlord.UIExtenderEx';  KeyDll='Bannerlord.UIExtenderEx.dll';  Extra=$null;                 Why='Lets mods change the UI. ROT needs it.';                  Nexus='https://www.nexusmods.com/mountandblade2bannerlord/mods/2102' }
        @{ Name='ButterLib';     Module='Bannerlord.ButterLib';     KeyDll='Bannerlord.ButterLib.dll';     Extra=$null;                 Why='Shared helper library many mods build on.';               Nexus='https://www.nexusmods.com/mountandblade2bannerlord/mods/2018' }
        @{ Name='MCM';           Module='Bannerlord.MBOptionScreen'; KeyDll='MCMv5.dll';                   Extra=$null;                 Why='Mod settings menu. ROT REQUIRES it - ROT.dll calls MCMv5 at runtime and CRASHES ~26s into a new game without it (even though ROT does not declare it as a dependency). Use official v5.11.3.';    Nexus='https://github.com/Aragas/Bannerlord.MBOptionScreen/releases/tag/v5.11.3' }
        @{ Name='BLSE';          Module=$null;                       KeyDll='Bannerlord.BLSE.LauncherEx.exe'; InBin=$true;             Why='The launcher ROT must run through.';                      Nexus='https://www.nexusmods.com/mountandblade2bannerlord/mods/1' }
    )
}

function Test-Dependencies {
    <# Returns a finding per dependency: Name, State, Detail, Advice, Optional #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Game)

    $bin  = $Game.BinPath
    $mods = $Game.ModulesPath
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($d in (Get-DependencySpec)) {
        $state='OK'; $detail=''; $advice=''

        if ($d.InBin) {
            # BLSE lives in the game bin, not Modules
            if (Test-Path (Join-Path $bin $d.KeyDll)) { $detail='installed correctly' }
            else { $state='MISSING'; $detail='not found in game bin folder'
                   $advice="Download $($d.Name) and extract so its 'bin' folder merges into the game folder. Get it: $($d.Nexus)" }
        }
        else {
            $folder = Join-Path $mods $d.Module
            $dllPath = Join-Path $folder "bin\Win64_Shipping_Client\$($d.KeyDll)"

            if (-not (Test-Path $folder)) {
                $state='MISSING'; $detail='module folder not in \Modules\'
                $advice="Download $($d.Name), extract the '$($d.Module)' folder into your Modules folder. Get it: $($d.Nexus)"
            }
            elseif (-not (Test-Path (Join-Path $folder 'SubModule.xml'))) {
                $state='BROKEN'; $detail='folder exists but SubModule.xml missing (bad/partial extract)'
                $advice="Delete the '$($d.Module)' folder and re-extract the download cleanly with 7-Zip."
            }
            elseif (-not (Test-Path $dllPath)) {
                # THE classic trap: folder is there but the actual code DLL isn't in bin.
                $state='INCOMPLETE'; $detail="folder present but '$($d.KeyDll)' is missing from its bin folder"
                $advice="The mod extracted wrong. Re-extract so '$($d.KeyDll)' lands in $($d.Module)\bin\Win64_Shipping_Client\."
            }
            else {
                $ver = ([regex]::Match((Get-Content (Join-Path $folder 'SubModule.xml') -Raw), '<Version\s*value\s*=\s*"([^"]+)"')).Groups[1].Value
                $ver = $ver -replace '^[ve]',''   # strip v/e prefix (e = early-access marker), same as everywhere else
                # STUB CHECK: ModReady/BetaDeps ships BetaDeps.*.dll stand-ins instead of the
                # real BUTR libraries. They reach the main menu but (when built for a different
                # game version) silently break campaign init -> the endless new-game loop.
                # (Test-IsStubDep lives in Common.ps1 - single source of truth.)
                if (Test-IsStubDep $folder) {
                    $state='STUB'
                    $detail="installed (v$ver) but this is a ModReady/BetaDeps STUB, not the official library"
                    $advice="Stubs reach the menu but can loop forever on a new campaign. Fix all deps in one click with menu option 4 (FIX my dependencies)."
                } else {
                    $detail = "installed (v$ver, official)"
                }
            }
        }

        $results.Add([pscustomobject]@{
            Name=$d.Name; State=$state; Detail=$detail; Advice=$advice
            Optional=[bool]$d.Optional; Why=$d.Why; Nexus=$d.Nexus
        })
    }
    $results
}

function Show-Dependencies {
    param([Parameter(Mandatory, ValueFromPipeline)] $Findings)
    begin { $all=[System.Collections.Generic.List[object]]::new() }
    process { foreach ($x in $Findings) { $all.Add($x) } }
    end {
    $Findings = $all
    Write-Host ""
    Write-Host "  Checking your mod dependencies..." -ForegroundColor Cyan
    Write-Host "  (These are the helper mods ROT and co-op need to run.)" -ForegroundColor DarkGray
    Write-Host ""
    foreach ($f in $Findings) {
        $tag = if ($f.Optional -and $f.State -ne 'OK') { ' (optional)' } else { '' }
        Write-Host ("  {0} {1,-14} {2}{3}" -f (Get-StatusIcon $f.State), $f.Name, $f.Detail, $tag) -ForegroundColor (Get-StatusColor $f.State)
        if ($f.State -ne 'OK') {
            Write-Host ("           why it matters: {0}" -f $f.Why) -ForegroundColor DarkGray
            Write-Host ("           what to do:     {0}" -f $f.Advice) -ForegroundColor Gray
        }
    }
    $bad = @($Findings | Where-Object { $_.State -ne 'OK' -and -not $_.Optional })
    Write-Host ""
    if ($bad.Count -eq 0) { Write-Host "  All required dependencies are correctly installed. You're good." -ForegroundColor Green }
    else { Write-Host "  $($bad.Count) required dependency issue(s) above. Fix those before launching, or the game will crash." -ForegroundColor Yellow }
    }
}
