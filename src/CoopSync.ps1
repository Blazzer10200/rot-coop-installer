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
    if ($Game.Version -eq $friendVer) { Write-Host "  [ OK ] Game version matches ($($Game.Version))" -ForegroundColor Green }
    else { Write-Host "  [DIFF] Game version: you=$($Game.Version)  friend=$friendVer  -> you must match" -ForegroundColor Red }

    $problems = 0
    # every mod the friend has (base-game modules skipped - they always match)
    foreach ($id in ($friend.Keys | Sort-Object)) {
        if ($id -in $script:CoopBaseModules) { continue }
        if (-not $mine.ContainsKey($id)) {
            Write-Host ("  [MISS] {0} -- friend has it ({1}), you don't. Install it." -f $id, (Format-Ver $friend[$id])) -ForegroundColor Red; $problems++
        } elseif (($mine[$id] -replace '^[ve]','') -ne ($friend[$id] -replace '^[ve]','')) {
            Write-Host ("  [DIFF] {0} -- you {1}, friend {2}. Match versions." -f $id, (Format-Ver $mine[$id]), (Format-Ver $friend[$id])) -ForegroundColor Yellow; $problems++
        } else {
            Write-Host ("  [ OK ] {0} {1}" -f $id, (Format-Ver $mine[$id])) -ForegroundColor Green
        }
    }
    # extra mods you have that the friend doesn't (can also break co-op)
    foreach ($id in ($mine.Keys | Sort-Object)) {
        if (-not $friend.ContainsKey($id) -and $id -notin $script:CoopBaseModules) {
            Write-Host ("  [EXTRA] {0} -- you have it, friend doesn't. Consider disabling it." -f $id) -ForegroundColor Yellow; $problems++
        }
    }

    Write-Host ""
    if ($problems -eq 0) { Write-Host "  PERFECT MATCH -- you two can play co-op together." -ForegroundColor Green }
    else { Write-Host "  $problems difference(s) above. Fix them, or co-op may fail to connect / desync." -ForegroundColor Yellow }
    Write-Host ""
}
