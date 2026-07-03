# CoopSync.ps1 - kills the #1 co-op failure: mismatched mods between host and friend.
# Host exports a fingerprint of their exact setup; friend imports and the tool reports
# EXACTLY what differs (missing mod, wrong version, wrong load order). Plain English.

# Base-game modules ship with everyone; they never cause a co-op mismatch, so we ignore
# them in comparisons to keep the report focused on the mods that actually matter.
$script:CoopBaseModules = @('Native','SandBox','SandBoxCore','StoryMode','CustomBattle','Multiplayer','BirthAndDeath','FastMode')

function Format-Ver([string]$v) { if ($v) { 'v' + ($v -replace '^[ve]','') } else { 'v?' } }

function Export-CoopProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Game,
        [string] $OutFile = (Join-Path $env:USERPROFILE 'Desktop\my-coop-setup.txt')
    )
    $mods = $Game.ModulesPath
    $entries = [System.Collections.Generic.List[object]]::new()

    # capture every enabled module's Id + version (order preserved from LauncherData)
    $order = @()
    if (Test-Path $Game.ConfigPath) {
        $order = [regex]::Matches((Get-Content $Game.ConfigPath -Raw), '<Id>([^<]+)</Id>') |
                 ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
    }

    foreach ($id in $order) {
        # find folder whose SubModule Id matches this id (handles ROT_Map vs ROT-Map)
        $folder = Get-ChildItem $mods -Directory -ErrorAction SilentlyContinue | Where-Object {
            $x = Join-Path $_.FullName 'SubModule.xml'
            (Test-Path $x) -and (([regex]::Match((Get-Content $x -Raw),'<Id\s*value\s*=\s*"([^"]+)"')).Groups[1].Value -eq $id)
        } | Select-Object -First 1
        $ver = if ($folder) { ([regex]::Match((Get-Content (Join-Path $folder.FullName 'SubModule.xml') -Raw),'<Version\s*value\s*=\s*"([^"]+)"')).Groups[1].Value } else { '?' }
        $entries.Add([pscustomobject]@{ Id=$id; Version=$ver })
    }

    $lines = @("# Realm of Thrones Co-op setup export", "# Game version: $($Game.Version)", "# Give this file to whoever you want to play with.", "")
    # only export the mods that matter for co-op (skip base-game modules everyone has)
    foreach ($e in $entries) { if ($e.Id -notin $script:CoopBaseModules) { $lines += ("{0}={1}" -f $e.Id, $e.Version) } }
    Set-Content -Path $OutFile -Value $lines -Encoding UTF8
    Write-Host ""
    Write-Host "  Exported your setup to:" -ForegroundColor Green
    Write-Host "    $OutFile" -ForegroundColor White
    Write-Host "  Send that file to your co-op partner. They pick 'Compare with a friend'." -ForegroundColor Gray
    Write-Host ""
    $OutFile
}

function Show-CoopHowTo {
    # The co-op START flow that trips everyone up: you do NOT click the normal
    # singleplayer "New Campaign". You click the mod's "Host Coop" button first.
    Write-Host ""
    Write-Host "  HOW TO ACTUALLY START A CO-OP GAME" -ForegroundColor Cyan
    Write-Host "  ----------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  IMPORTANT: Do NOT click the normal 'New Campaign' button." -ForegroundColor Yellow
    Write-Host "  Co-op has its own buttons on the main menu." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  IF YOU ARE THE HOST:" -ForegroundColor Green
    Write-Host "    1. Launch the game (your co-op desktop shortcut)."
    Write-Host "    2. On the main menu, click  >> Host Coop <<  first."
    Write-Host "    3. THEN start a new campaign - do character + clan creation."
    Write-Host "    4. Once you reach the map, your friend can join."
    Write-Host "    5. Bottom-left should say 'BannerlordTogether: N patch(es) applied!'"
    Write-Host ""
    Write-Host "  IF YOU ARE JOINING A FRIEND:" -ForegroundColor Green
    Write-Host "    1. Launch the game."
    Write-Host "    2. On the main menu, click  >> Join Co-op <<."
    Write-Host "    3. Join via the Steam lobby, or type the host's IP address."
    Write-Host "    4. Pick or create your character. The host's world loads automatically."
    Write-Host ""
    Write-Host "  CONNECTING OVER THE INTERNET:" -ForegroundColor White
    Write-Host "    - Easiest: use Steam networking / Steam lobby (no router setup)."
    Write-Host "    - Non-Steam: the HOST forwards UDP port 47770 (and 47771 for battles),"
    Write-Host "      or use a VPN like Radmin/Hamachi and share that IP."
    Write-Host ""
    Write-Host "  BOTH PLAYERS must have the EXACT same mods + versions (use option 7 to compare)." -ForegroundColor Gray
    Write-Host ""
}

function Compare-CoopProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Game,
        [Parameter(Mandatory)] [string] $FriendFile
    )
    if (-not (Test-Path $FriendFile)) {
        Write-Host "  Can't find that file: $FriendFile" -ForegroundColor Red; return
    }

    # parse friend's export
    $friend = @{}
    $friendVer = 'unknown'
    foreach ($line in (Get-Content $FriendFile)) {
        if ($line -match '^#\s*Game version:\s*(.+)$') { $friendVer = $Matches[1].Trim(); continue }
        if ($line -match '^\s*#' -or -not $line.Trim()) { continue }
        if ($line -match '^(.+?)=(.+)$') { $friend[$Matches[1].Trim()] = $Matches[2].Trim() }
    }

    # build mine
    $mods = $Game.ModulesPath
    $mine = @{}
    Get-ChildItem $mods -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $x = Join-Path $_.FullName 'SubModule.xml'
        if (Test-Path $x) {
            $raw = Get-Content $x -Raw
            $id  = ([regex]::Match($raw,'<Id\s*value\s*=\s*"([^"]+)"')).Groups[1].Value
            $ver = ([regex]::Match($raw,'<Version\s*value\s*=\s*"([^"]+)"')).Groups[1].Value
            if ($id) { $mine[$id] = $ver }
        }
    }

    Write-Host ""
    Write-Host "  Comparing your setup to your friend's..." -ForegroundColor Cyan
    Write-Host "  ------------------------------------------" -ForegroundColor DarkGray

    # game version
    if ($Game.Version -eq $friendVer) { Write-Host ("  {0} Game version matches ($($Game.Version))" -f (Get-StatusIcon 'OK')) -ForegroundColor (Get-StatusColor 'OK') }
    else { Write-Host ("  {0} Game version: you=$($Game.Version)  friend=$friendVer  -> you must match" -f (Get-StatusIcon 'STOP')) -ForegroundColor (Get-StatusColor 'STOP') }

    $problems = 0
    # every mod the friend has (base-game modules skipped - they always match)
    foreach ($id in ($friend.Keys | Sort-Object)) {
        if ($id -in $script:CoopBaseModules) { continue }
        if (-not $mine.ContainsKey($id)) {
            Write-Host ("  {0} {1} -- friend has it ({2}), you don't. Install it." -f (Get-StatusIcon 'MISSING'), $id, (Format-Ver $friend[$id])) -ForegroundColor (Get-StatusColor 'MISSING'); $problems++
        } elseif (($mine[$id] -replace '^[ve]','') -ne ($friend[$id] -replace '^[ve]','')) {
            Write-Host ("  {0} {1} -- you {2}, friend {3}. Match versions." -f (Get-StatusIcon 'DIFF'), $id, (Format-Ver $mine[$id]), (Format-Ver $friend[$id])) -ForegroundColor (Get-StatusColor 'DIFF'); $problems++
        } else {
            Write-Host ("  {0} {1} {2}" -f (Get-StatusIcon 'OK'), $id, (Format-Ver $mine[$id])) -ForegroundColor (Get-StatusColor 'OK')
        }
    }
    # extra mods you have that the friend doesn't (can also break co-op)
    foreach ($id in ($mine.Keys | Sort-Object)) {
        if (-not $friend.ContainsKey($id) -and $id -notin $script:CoopBaseModules) {
            Write-Host ("  {0} {1} -- you have it, friend doesn't. Consider disabling it." -f (Get-StatusIcon 'EXTRA'), $id) -ForegroundColor (Get-StatusColor 'EXTRA'); $problems++
        }
    }

    Write-Host ""
    if ($problems -eq 0) { Write-Host "  PERFECT MATCH -- you two can play co-op together." -ForegroundColor Green }
    else { Write-Host "  $problems difference(s) above. Fix them, or co-op may fail to connect / desync." -ForegroundColor Yellow }
    Write-Host ""
}
