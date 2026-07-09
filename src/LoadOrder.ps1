# LoadOrder.ps1 - writes a correct, dependency-safe load order to LauncherData.xml.
# Fixes the two real failures we hit: launcher rescrambling the order, and every
# module getting set to IsSelected=false (which silently kills the Play button).

function Write-LoadOrder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Game,   # from Find-Bannerlord
        [Parameter(Mandatory)] $Prof,   # from Get-CompatProfile
        [switch] $NoBackup              # by default we back up the existing file first
    )

    $cfg = $Game.ConfigPath
    if (-not (Test-Path (Split-Path $cfg))) {
        New-Item -ItemType Directory -Force -Path (Split-Path $cfg) | Out-Null
    }
    if (-not $NoBackup -and (Test-Path $cfg)) {
        $stamp = (Get-Item $cfg).LastWriteTime.ToString('yyyyMMdd-HHmmss')
        Copy-Item $cfg "$cfg.bak-$stamp" -Force
    }

    $ver   = $Prof.gameVersion
    # Only write modules that actually exist on THIS machine. The profile's full list
    # includes optional pieces (e.g. BannerlordTogether for a solo-only player) - listing
    # a module the launcher can't find just invites it to rewrite the file again.
    $order = @($Prof.loadOrder | Where-Object { Test-Path (Join-Path $Game.ModulesPath $_) })
    $skipped = @($Prof.loadOrder | Where-Object { $_ -notin $order })

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<?xml version="1.0" encoding="utf-8"?>')
    [void]$sb.AppendLine('<UserData xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">')
    [void]$sb.AppendLine('  <GameType>Singleplayer</GameType>')
    [void]$sb.AppendLine('  <SingleplayerData><ModDatas>')
    foreach ($id in $order) {
        [void]$sb.AppendLine("      <UserModData><Id>$id</Id><LastKnownVersion>$ver</LastKnownVersion><IsSelected>true</IsSelected></UserModData>")
    }
    [void]$sb.AppendLine('  </ModDatas></SingleplayerData>')
    [void]$sb.AppendLine('  <MultiplayerData><ModDatas>')
    [void]$sb.AppendLine("      <UserModData><Id>Native</Id><LastKnownVersion>$ver</LastKnownVersion><IsSelected>true</IsSelected></UserModData>")
    [void]$sb.AppendLine("      <UserModData><Id>Multiplayer</Id><LastKnownVersion>$ver</LastKnownVersion><IsSelected>true</IsSelected></UserModData>")
    [void]$sb.AppendLine('  </ModDatas></MultiplayerData>')
    [void]$sb.AppendLine('  <DLLCheckData><DLLData /></DLLCheckData>')
    [void]$sb.AppendLine('</UserData>')

    [System.IO.File]::WriteAllText($cfg, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
    "Load order reset: $($order.Count) modules enabled, correct order (backup saved)$(if ($skipped) { ", skipped not-installed: $($skipped -join ', ')" })."
}
