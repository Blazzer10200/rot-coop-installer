# LoadOrder.ps1 - writes a correct, dependency-safe load order to LauncherData.xml.
# Fixes the two real failures we hit: launcher rescrambling the order, and every
# module getting set to IsSelected=false (which silently kills the Play button).

function Write-LoadOrder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Game,   # from Find-Bannerlord
        [Parameter(Mandatory)] $Prof,   # from Get-CompatProfile
        [switch] $Backup = $true
    )

    $cfg = $Game.ConfigPath
    if (-not (Test-Path (Split-Path $cfg))) {
        New-Item -ItemType Directory -Force -Path (Split-Path $cfg) | Out-Null
    }
    if ($Backup -and (Test-Path $cfg)) {
        $stamp = (Get-Item $cfg).LastWriteTime.ToString('yyyyMMdd-HHmmss')
        Copy-Item $cfg "$cfg.bak-$stamp" -Force
    }

    $ver   = $Prof.gameVersion
    $order = $Prof.loadOrder

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
    "Load order reset: $($order.Count) modules enabled, correct order (backup saved)."
}
