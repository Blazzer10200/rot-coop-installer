# Launch.ps1 - one-click "Play". Runs preflight, launches the game through BLSE,
# then immediately opens the friendly loading screen. This is the button that turns
# a toolbox into "the thing you click to play."

function Start-RotCoop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Game,
        $Prof = $null,
        [switch] $SkipPreflight,
        [switch] $NoWatch
    )

    # 1) Preflight gate (unless skipped)
    if (-not $SkipPreflight -and (Get-Command Invoke-Preflight -ErrorAction SilentlyContinue)) {
        $result = Invoke-Preflight -Game $Game -Prof $Prof | Show-Preflight
        if (-not $result.Go) {
            Write-Host "  Not launching. Fix the [STOP] items above, then try again." -ForegroundColor Yellow
            Write-Host "  (Tip: menu option 3 auto-fixes most problems.)" -ForegroundColor DarkGray
            return
        }
    }

    # 2) Locate the BLSE launcher (the ONLY correct way to launch modded ROT)
    $launcher = Join-Path $Game.BinPath 'Bannerlord.BLSE.LauncherEx.exe'
    if (-not (Test-Path $launcher)) {
        $launcher = Join-Path $Game.BinPath 'Bannerlord.BLSE.Launcher.exe'   # fallback
    }
    if (-not (Test-Path $launcher)) {
        Write-Host "  Could not find the BLSE launcher. Is BLSE installed?" -ForegroundColor Red
        return
    }

    # 3) Launch it
    Write-Host ""
    Write-Host "  Launching Bannerlord through BLSE..." -ForegroundColor Cyan
    try {
        Start-Process -FilePath $launcher -WorkingDirectory $Game.BinPath
    } catch {
        Write-Host "  Failed to start the launcher: $_" -ForegroundColor Red
        return
    }

    Write-Host "  In the launcher: make sure the 'Singleplayer' tab is selected, then click Play." -ForegroundColor Gray
    Write-Host "  (Click Yes on any yellow caution popup - that's normal with mods.)" -ForegroundColor DarkGray

    # 4) Open the friendly loading screen so they never stare at a blank void
    if (-not $NoWatch -and (Get-Command Watch-BannerlordLoad -ErrorAction SilentlyContinue)) {
        Write-Host ""
        Write-Host "  When you click Play, this window will track the load for you." -ForegroundColor Gray
        Write-Host "  Press Enter here once you've clicked Play in the launcher..." -ForegroundColor DarkGray
        $null = Read-Host
        Watch-BannerlordLoad
    }
}
