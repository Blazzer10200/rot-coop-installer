# FixDependencies.ps1 - the auto-repair that fixes the #1 co-op killer.
#
# THE problem this solves: most ROT/co-op guides tell people to install the "ModReady"
# (BetaDeps) dependency bundle. Those are STUB copies of Harmony/ButterLib/UIExtenderEx/MCM.
# They reach the main menu, so people think they're fine - but when the bundle is built for
# a different game version than you're running, they silently break campaign init and the
# game loops forever on a new game (no crash, no error). And ROT also needs MCM at runtime
# or it crashes ~26s in. This module replaces the stubs with the OFFICIAL BUTR libraries
# that match, and installs the correct MCM - fully automatically, from GitHub (no login).
#
# Everything is backed up first and the game must be closed.

# Official dependency sources. GitHub releases = direct download, no Nexus login.
# Pinned tags are the versions verified working with ROT 7.1 on Bannerlord 1.3.15.
function Get-OfficialDepSources {
    @(
        @{ Name='Harmony';      Module='Bannerlord.Harmony';       Repo='BUTR/Bannerlord.Harmony';            Tag='v2.4.2.225'; Asset='Bannerlord.Harmony.7z' }
        @{ Name='ButterLib';    Module='Bannerlord.ButterLib';     Repo='BUTR/Bannerlord.ButterLib';          Tag='v2.10.3';    Asset='Bannerlord.ButterLib.7z' }
        @{ Name='UIExtenderEx'; Module='Bannerlord.UIExtenderEx';  Repo='BUTR/Bannerlord.UIExtenderEx';       Tag='v2.13.2';    Asset='Bannerlord.UIExtenderEx.7z' }
        @{ Name='MCM';          Module='Bannerlord.MBOptionScreen'; Repo='Aragas/Bannerlord.MBOptionScreen';   Tag='v5.11.3';    Asset='Bannerlord.MBOptionScreen.7z' }
    )
}

# Find a 7-Zip executable (needed to extract the .7z release assets).
function Get-SevenZip {
    $candidates = @(
        "$env:ProgramFiles\7-Zip\7z.exe",
        "${env:ProgramFiles(x86)}\7-Zip\7z.exe",
        "$env:ProgramW6432\7-Zip\7z.exe"
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    $cmd = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

# Resolve the actual download URL for a release asset (falls back to the API if the
# predictable /releases/download/<tag>/<asset> path 404s).
function Resolve-AssetUrl {
    param([string]$Repo, [string]$Tag, [string]$Asset)
    $direct = "https://github.com/$Repo/releases/download/$Tag/$Asset"
    try {
        $h = Invoke-WebRequest -Uri $direct -Method Head -Headers @{ 'User-Agent'='rot-tool' } -TimeoutSec 20 -ErrorAction Stop
        return $direct
    } catch {
        try {
            $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/tags/$Tag" -Headers @{ 'User-Agent'='rot-tool' } -TimeoutSec 20
            $a = $rel.assets | Where-Object { $_.name -match '\.(7z|zip)$' } | Select-Object -First 1
            if ($a) { return $a.browser_download_url }
        } catch {}
    }
    return $null
}

function Repair-Dependencies {
    <#
      Downloads + installs the official BUTR dependencies, replacing any ModReady/BetaDeps
      stubs and installing MCM if missing. Backs up anything it replaces. Game must be closed.
      Returns human-readable report lines.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Game,
        [string] $BackupRoot = (Join-Path $env:USERPROFILE "Downloads\_rot_installer_backup"),
        [switch] $Force   # skip the "already official" short-circuit and reinstall anyway
    )
    $ProgressPreference = 'SilentlyContinue'
    $report = [System.Collections.Generic.List[string]]::new()
    $mods = $Game.ModulesPath

    # 0) game must be closed (locked DLLs can't be replaced)
    $live = Get-Process -Name '*Bannerlord*' -ErrorAction SilentlyContinue | Where-Object { -not $_.HasExited }
    if ($live) {
        # confirm with a real lock probe before refusing
        $probe = Get-ChildItem (Join-Path $mods 'Bannerlord.Harmony') -Recurse -Filter *.dll -ErrorAction SilentlyContinue | Select-Object -First 1
        $locked = $false
        if ($probe) { try { $fs=[IO.File]::Open($probe.FullName,'Open','ReadWrite','None'); $fs.Close() } catch { $locked = $true } }
        if ($locked) { $report.Add("STOPPED: the game is still running. Close Bannerlord (and its launcher) fully, then run this again."); return $report }
    }

    # 1) need 7-Zip to extract release assets
    $sz = Get-SevenZip
    if (-not $sz) {
        $report.Add("STOPPED: 7-Zip is required to extract the downloads. Install it from https://www.7-zip.org/ (or 'winget install 7zip.7zip'), then run this again.")
        return $report
    }

    $work = Join-Path $env:TEMP "rot_dep_repair"
    if (Test-Path $work) { Get-ChildItem $work -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null

    foreach ($dep in (Get-OfficialDepSources)) {
        $dst = Join-Path $mods $dep.Module
        $bin = Join-Path $dst 'bin\Win64_Shipping_Client'

        # is it already the official one (no BetaDeps stub, correct key dll)? skip unless -Force
        $isStub = (Test-Path (Join-Path $bin 'BetaDeps.Foundation.dll')) -or (Test-Path (Join-Path $bin 'BetaDeps.Harmony.dll'))
        $exists = Test-Path $dst
        if ($exists -and -not $isStub -and -not $Force) {
            $report.Add("$($dep.Name): already official - left as-is.")
            continue
        }

        # download
        $url = Resolve-AssetUrl -Repo $dep.Repo -Tag $dep.Tag -Asset $dep.Asset
        if (-not $url) { $report.Add("$($dep.Name): FAILED to find a download URL (skipped). Get it manually from https://github.com/$($dep.Repo)/releases/tag/$($dep.Tag)"); continue }
        $arc = Join-Path $work "$($dep.Name).7z"
        try {
            Invoke-WebRequest -Uri $url -OutFile $arc -Headers @{ 'User-Agent'='rot-tool' } -TimeoutSec 120 -ErrorAction Stop
        } catch {
            $report.Add("$($dep.Name): download FAILED ($($_.Exception.Message)). Get it manually from https://github.com/$($dep.Repo)/releases/tag/$($dep.Tag)"); continue
        }

        # extract
        $ex = Join-Path $work $dep.Name
        & $sz x $arc "-o$ex" -y 2>&1 | Out-Null
        $srcMod = Get-ChildItem $ex -Recurse -Directory -Filter $dep.Module -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $srcMod) {
            # some archives put the module at the root of the archive
            if (Test-Path (Join-Path $ex 'SubModule.xml')) { $srcMod = Get-Item $ex }
        }
        if (-not $srcMod) { $report.Add("$($dep.Name): extracted but could not find the '$($dep.Module)' folder inside (skipped)."); continue }

        # back up existing (stub or old) then install official
        if ($exists) {
            $bdir = Join-Path $BackupRoot ("deps_replaced\" + $dep.Module)
            New-Item -ItemType Directory -Force -Path (Split-Path $bdir) | Out-Null
            if (Test-Path $bdir) { Get-ChildItem $bdir -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
            Move-Item $dst $bdir -Force
        }
        Copy-Item $srcMod.FullName $dst -Recurse -Force
        $ver = ([regex]::Match((Get-Content (Join-Path $dst 'SubModule.xml') -Raw),'<Version value="([^"]+)"')).Groups[1].Value
        $what = if ($isStub) { "replaced STUB with official" } elseif ($exists) { "reinstalled official" } else { "installed official" }
        $report.Add("$($dep.Name): $what $ver")
    }

    $report.Add("Done. Backups (if any) are in $BackupRoot\deps_replaced. Now run 'Fix common problems' once more to reset the load order, then launch.")
    $report
}
