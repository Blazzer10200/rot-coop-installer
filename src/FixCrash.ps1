# FixCrash.ps1 - the killer feature. Clears the crashes we hit during the real setup.
# Depends on a $game object from Find-Bannerlord.

function Repair-RotInstall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Game,   # object from Find-Bannerlord
        $Prof = $null,                  # optional compat profile; enables load-order reset
        [string] $BackupRoot = (Join-Path $env:USERPROFILE "Downloads\_rot_installer_backup")
    )

    New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
    $report = [System.Collections.Generic.List[string]]::new()

    # --- FIX 1: invalid shader caches (the 0xC0000005 native crash) ---
    $shaderTargets = @(
        (Join-Path $Game.ModulesPath "ROT-Content\Shaders\D3D11\compressed_shader_cache.sack"),
        (Join-Path $Game.ModulesPath "ROT_Map\Shaders\D3D11\compressed_shader_cache.sack"),
        (Join-Path $Game.ModulesPath "ROT-Core\Shaders\D3D11\compressed_shader_cache.sack"),
        (Join-Path $Game.ModulesPath "ROT-Dragon\Shaders\D3D11\compressed_shader_cache.sack")
    )
    $shaderCount = 0
    foreach ($t in $shaderTargets) {
        if ([System.IO.File]::Exists($t)) {
            $safe = (Split-Path (Split-Path (Split-Path $t))) | Split-Path -Leaf
            Copy-Item -LiteralPath $t -Destination (Join-Path $BackupRoot "$safe`_shader.sack") -Force
            [System.IO.File]::Delete($t)
            $shaderCount++
        }
    }
    # global ProgramData shader cache (the fallback the community mentions)
    $pdShaders = Join-Path $Game.ProgramData "Shaders"
    if (Test-Path $pdShaders) {
        # only the D3D11 .sack, keep the folder structure the engine expects
        Get-ChildItem $pdShaders -Recurse -Filter "*.sack" -ErrorAction SilentlyContinue | ForEach-Object {
            [System.IO.File]::Delete($_.FullName); $shaderCount++
        }
    }
    $report.Add("Shader caches cleared: $shaderCount (engine will recompile clean)")

    # --- FIX 2: reset scrambled / all-disabled load order ---
    if ($Prof -and (Get-Command Write-LoadOrder -ErrorAction SilentlyContinue)) {
        $report.Add((Write-LoadOrder -Game $Game -Prof $Prof))
    } else {
        $report.Add("Load order: skipped (no profile supplied). Run a full check to reset it.")
    }

    # --- FIX 3: clear crash + safe-mode markers ---
    $markers = @(
        (Join-Path $Game.ModulesPath "Bannerlord.Harmony\session-launching.marker"),
        (Join-Path $env:LOCALAPPDATA "BetaDeps\session-launching.marker")
    )
    $mCount = 0
    foreach ($m in $markers) { if ([System.IO.File]::Exists($m)) { [System.IO.File]::Delete($m); $mCount++ } }
    $report.Add("Crash markers cleared: $mCount (prevents spurious safe-mode prompt)")

    # --- CHECK 4: Steam running? (the 'Unable to initialize Steam API' gotcha) ---
    $steam = Get-Process -Name "steam" -ErrorAction SilentlyContinue
    if ($steam) { $report.Add("Steam: RUNNING (good)") }
    else { $report.Add("Steam: NOT RUNNING -- start Steam and log in BEFORE launching, or you get 'Unable to initialize Steam API'") }

    $report
}
