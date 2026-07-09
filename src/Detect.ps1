# Detect.ps1 - locate Bannerlord install, version, War Sails state
# Part of ROT Co-op Installer. Dot-source or call Find-Bannerlord.

function Find-Bannerlord {
    [CmdletBinding()]
    param()

    $candidates = @()

    # 1) Parse every Steam library from libraryfolders.vdf
    $steamRoots = @(
        "${env:ProgramFiles(x86)}\Steam",
        "$env:ProgramFiles\Steam"
    ) | Where-Object { Test-Path $_ }

    foreach ($sr in $steamRoots) {
        $vdf = Join-Path $sr "steamapps\libraryfolders.vdf"
        if (Test-Path $vdf) {
            $paths = Select-String -Path $vdf -Pattern '"path"\s+"([^"]+)"' -AllMatches |
                     ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value -replace '\\\\','\' }
            foreach ($p in $paths) {
                $candidates += Join-Path $p "steamapps\common\Mount & Blade II Bannerlord"
            }
        }
        $candidates += Join-Path $sr "steamapps\common\Mount & Blade II Bannerlord"
    }

    $game = $candidates | Where-Object { Test-Path (Join-Path $_ "bin\Win64_Shipping_Client") } | Select-Object -First 1
    if (-not $game) {
        return [pscustomobject]@{ Found = $false; Path = $null; Version = $null; WarSails = $null }
    }

    # 2) Version from Version.xml - match the Singleplayer node specifically (not the first Value=)
    $verXml = Join-Path $game "bin\Win64_Shipping_Client\Version.xml"
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
        ModulesPath     = Join-Path $game "Modules"
        BinPath         = Join-Path $game "bin\Win64_Shipping_Client"
        Version         = $version
        VersionNorm     = $versionNorm
        WarSails        = $warSails
        WarSailsEnabled = $warSailsEnabled
        RotVersion      = (Get-RotVersion -ModulesPath (Join-Path $game "Modules"))
        ConfigPath      = $configPath
        ProgramData     = (Get-BannerlordProgramData)
    }
}
