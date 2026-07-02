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

    # 3) War Sails DLC: detect the actual DLC module folder (not the always-present Multiplayer).
    #    War Sails ships module folders like "Warsails" / "SailingShips" - probe common names.
    $warSailsFolders = @('Warsails','WarSails','SailingShips','Naval') |
        Where-Object { Test-Path (Join-Path $game "Modules\$_") }
    $warSails = [bool]$warSailsFolders

    [pscustomobject]@{
        Found        = $true
        Path         = $game
        ModulesPath  = Join-Path $game "Modules"
        BinPath      = Join-Path $game "bin\Win64_Shipping_Client"
        Version      = $version
        VersionNorm  = $versionNorm
        WarSails     = $warSails
        ConfigPath   = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "Mount and Blade II Bannerlord\Configs\LauncherData.xml"
        ProgramData  = "C:\ProgramData\Mount and Blade II Bannerlord"
    }
}
