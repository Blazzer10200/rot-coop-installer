# Detect.ps1 - locate Bannerlord install, version, War Sails state
# Part of ROT Co-op Installer. Dot-source or call Find-Bannerlord.
#
# Searches every store the game ships on, in this order:
#   0. A game folder the user pointed us at before (saved in tool settings)
#   1. Steam  - registry install path + every library in libraryfolders.vdf
#   2. GOG    - registry (Galaxy + offline installer both write it) + default folders
#   3. Epic   - the launcher's install manifests in ProgramData
#   4. Xbox / Game Pass - <drive>:\XboxGames\...\Content (uses a different bin folder)

# A folder counts as a Bannerlord install if it has a client bin + a Modules folder.
# Steam/GOG/Epic use bin\Win64_Shipping_Client; Game Pass uses
# bin\Gaming.Desktop.x64_Shipping_Client (BLSE ships launchers for both).
function Test-BannerlordRoot {
    param([string] $Path)
    if (-not $Path) { return $false }
    $hasBin = (Test-Path (Join-Path $Path 'bin\Win64_Shipping_Client')) -or
              (Test-Path (Join-Path $Path 'bin\Gaming.Desktop.x64_Shipping_Client'))
    [bool]($hasBin -and (Test-Path (Join-Path $Path 'Modules')))
}

function Get-SteamGameCandidates {
    $roots = [System.Collections.Generic.List[string]]::new()
    # registry first - catches Steam installed anywhere, any drive
    foreach ($rk in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam')) {
        $v = Get-ItemProperty -Path $rk -ErrorAction SilentlyContinue
        foreach ($prop in @('SteamPath','InstallPath')) {
            if ($v -and $v.$prop) { $roots.Add(($v.$prop -replace '/','\')) }
        }
    }
    # default locations as fallback (registry can be missing on repaired installs)
    foreach ($d in @("${env:ProgramFiles(x86)}\Steam", "$env:ProgramFiles\Steam")) { $roots.Add($d) }

    $candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($sr in ($roots | Select-Object -Unique | Where-Object { $_ -and (Test-Path $_) })) {
        # every library folder Steam knows about (games often live on a second drive)
        $vdf = Join-Path $sr 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            $paths = Select-String -Path $vdf -Pattern '"path"\s+"([^"]+)"' -AllMatches |
                     ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value -replace '\\\\','\' }
            foreach ($p in $paths) { $candidates.Add((Join-Path $p 'steamapps\common\Mount & Blade II Bannerlord')) }
        }
        $candidates.Add((Join-Path $sr 'steamapps\common\Mount & Blade II Bannerlord'))
    }
    $candidates
}

function Get-GogGameCandidates {
    $candidates = [System.Collections.Generic.List[string]]::new()
    # GOG writes every installed game under this key (Galaxy AND offline installers)
    foreach ($hive in @('HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games', 'HKLM:\SOFTWARE\GOG.com\Games')) {
        Get-ChildItem $hive -ErrorAction SilentlyContinue | ForEach-Object {
            $g = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($g -and ("$($g.gameName)$($g.path)" -match 'Bannerlord') -and $g.path) { $candidates.Add($g.path) }
        }
    }
    # common manual locations
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        $candidates.Add("$($drive.Root)GOG Games\Mount & Blade II Bannerlord")
    }
    $candidates
}

function Get-EpicGameCandidates {
    $candidates = [System.Collections.Generic.List[string]]::new()
    $manifests = Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests'
    Get-ChildItem $manifests -Filter '*.item' -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $m = Get-Content $_.FullName -Raw | ConvertFrom-Json
            if ("$($m.DisplayName)" -match 'Bannerlord' -and $m.InstallLocation) { $candidates.Add($m.InstallLocation) }
        } catch { }
    }
    $candidates
}

function Get-XboxGameCandidates {
    $candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        $xg = Join-Path $drive.Root 'XboxGames'
        Get-ChildItem $xg -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'Bannerlord' } |
            ForEach-Object { $candidates.Add((Join-Path $_.FullName 'Content')) }
    }
    $candidates
}

function Find-Bannerlord {
    [CmdletBinding()]
    param()

    # ordered candidate list, each tagged with the store it came from
    $tagged = [System.Collections.Generic.List[object]]::new()
    $saved = Get-ToolSettings
    if ($saved -and $saved.gamePath) { $tagged.Add(@{ Path = $saved.gamePath; Platform = "$(if ($saved.gamePlatform) { $saved.gamePlatform } else { 'custom' })" }) }
    foreach ($p in (Get-SteamGameCandidates)) { $tagged.Add(@{ Path = $p; Platform = 'steam' }) }
    foreach ($p in (Get-GogGameCandidates))   { $tagged.Add(@{ Path = $p; Platform = 'gog' }) }
    foreach ($p in (Get-EpicGameCandidates))  { $tagged.Add(@{ Path = $p; Platform = 'epic' }) }
    foreach ($p in (Get-XboxGameCandidates))  { $tagged.Add(@{ Path = $p; Platform = 'xbox' }) }

    $hit = $tagged | Where-Object { Test-BannerlordRoot $_.Path } | Select-Object -First 1
    if (-not $hit) {
        return [pscustomobject]@{ Found = $false; Path = $null; Platform = $null; Version = $null; WarSails = $null }
    }
    $game = $hit.Path
    $platform = $hit.Platform

    # resolve the client bin: Steam/GOG/Epic layout first, Game Pass layout second
    $binPath = Join-Path $game 'bin\Win64_Shipping_Client'
    if (-not (Test-Path $binPath)) {
        $binPath = Join-Path $game 'bin\Gaming.Desktop.x64_Shipping_Client'
        if ($platform -eq 'custom') { $platform = 'xbox' }   # that bin only exists on Game Pass builds
    }

    # 2) Version from Version.xml - match the Singleplayer node specifically (not the first Value=)
    $verXml = Join-Path $binPath 'Version.xml'
    $version = if (Test-Path $verXml) {
        $raw = Get-Content $verXml -Raw
        $m = [regex]::Match($raw, '<Singleplayer[^>]*Value="([^"]+)"')
        if (-not $m.Success) { $m = [regex]::Match($raw, 'Value="(v?[\d.]+)"') }  # fallback
        if ($m.Success) { $m.Groups[1].Value } else { 'unknown' }
    } else { 'unknown' }
    $versionNorm = $version -replace '^[ve]', ''   # strip v/e prefix for comparison

    # 3) War Sails DLC. The DLC's real module folder is 'NavalDLC' (assembly NavalDLC.dll -
    #    verified from a live BLSE crash report). The old guess-list ('Warsails',
    #    'SailingShips', 'Naval') never matched it, so War Sails detection NEVER fired.
    #    Old names kept as fallbacks in case a future build renames the folder.
    $warSailsFolders = @((Get-WarSailsModuleName),'Warsails','WarSails','SailingShips') |
        Where-Object { Test-Path (Join-Path $game "Modules\$_") }
    $warSails = [bool]$warSailsFolders

    # installed != enabled. Co-op only breaks when the DLC module is ENABLED in the
    # launcher; owning it with the toggle off is fine. Read LauncherData for the state.
    $configPath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "Mount and Blade II Bannerlord\Configs\LauncherData.xml"
    $warSailsEnabled = $false
    if ($warSails -and (Test-Path $configPath)) {
        $cfgRaw = Get-Content $configPath -Raw
        $m = [regex]::Match($cfgRaw, "<Id>$(Get-WarSailsModuleName)</Id>.*?<IsSelected>(true|false)</IsSelected>", 'Singleline')
        if ($m.Success) { $warSailsEnabled = ($m.Groups[1].Value -eq 'true') }
        else { $warSailsEnabled = $warSails }   # installed but never seen by launcher: assume it'll load
    } elseif ($warSails) {
        $warSailsEnabled = $true                 # no launcher config to say otherwise
    }

    [pscustomobject]@{
        Found           = $true
        Path            = $game
        Platform        = $platform
        ModulesPath     = Join-Path $game "Modules"
        BinPath         = $binPath
        Version         = $version
        VersionNorm     = $versionNorm
        WarSails        = $warSails
        WarSailsEnabled = $warSailsEnabled
        RotVersion      = (Get-RotVersion -ModulesPath (Join-Path $game "Modules"))
        ConfigPath      = $configPath
        ProgramData     = (Get-BannerlordProgramData)
    }
}
