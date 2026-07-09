# CrashReport.ps1 - reads a BLSE crash report and explains it in plain English.
# Born 2026-07-09: a friend's "it just crashes" was ROT 8.0 Warsails without the War
# Sails DLC - obvious in the report's first ten lines, invisible to a player. When the
# game crashes, BLSE offers to save a crash report zip; this reads that zip FOR the
# player and matches it against the crashes we know, so nobody has to eyeball JSON.

function Read-CrashReport {
    <# Accepts a BLSE crash-report .zip, an extracted folder, or crashreport.json itself.
       Returns the parsed report object, or $null (with a printed reason) on failure. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)
    $p = $Path.Trim('"',' ')
    if (-not (Test-Path $p)) { Write-Host "  Can't find that file: $p" -ForegroundColor Red; return $null }

    $json = $null
    if ((Get-Item $p).PSIsContainer) {
        $json = Get-ChildItem $p -Recurse -Filter 'crashreport.json' -ErrorAction SilentlyContinue | Select-Object -First 1 | ForEach-Object { $_.FullName }
    } elseif ($p -match '\.zip$') {
        $tmp = Join-Path $env:TEMP 'rot_crash_report'
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
        try { Expand-Archive -LiteralPath $p -DestinationPath $tmp -Force -ErrorAction Stop }
        catch { Write-Host "  Couldn't unzip it: $($_.Exception.Message)" -ForegroundColor Red; return $null }
        $json = Get-ChildItem $tmp -Recurse -Filter 'crashreport.json' -ErrorAction SilentlyContinue | Select-Object -First 1 | ForEach-Object { $_.FullName }
    } elseif ($p -match '\.json$') {
        $json = $p
    }
    if (-not $json -or -not (Test-Path $json)) {
        Write-Host "  No crashreport.json in there - is this a BLSE crash report? (When the game" -ForegroundColor Red
        Write-Host "  crashes, BLSE shows a dialog with a 'Save report' button - that zip is what I read.)" -ForegroundColor Red
        return $null
    }
    try { Get-Content $json -Raw | ConvertFrom-Json }
    catch { Write-Host "  crashreport.json is unreadable: $($_.Exception.Message)" -ForegroundColor Red; $null }
}

function Show-CrashDiagnosis {
    <# Prints what happened + what to do. Matching order: most-specific known cause first,
       generic "the crash came from module X" fallback last. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Report)

    $e   = $Report.Exception
    $msg = "$(if ($e) { $e.Message })"
    $typ = "$(if ($e) { $e.Type })"
    $src = "$(if ($e) { $e.SourceModuleId })"

    Write-Host ""
    Write-Host "  CRASH REPORT DIAGNOSIS" -ForegroundColor Cyan
    Write-Host "  ----------------------" -ForegroundColor DarkGray
    $meta = $Report.Metadata
    if ($meta) { Write-Host "  Game: Bannerlord $($meta.GameVersion)   Loader: $($meta.LoaderPluginProviderName) $($meta.LoaderPluginProviderVersion)" -ForegroundColor Gray }
    if ($typ)  { Write-Host "  Error: $typ" -ForegroundColor Gray }
    if ($msg)  { Write-Host "  Says:  $($msg -replace '\s+',' ')" -ForegroundColor Gray }
    if ($src)  { Write-Host "  From:  module '$src'" -ForegroundColor Gray }

    # their mod list, so version mismatches jump out
    $rotMods = @($Report.Modules | Where-Object { "$($_.Id)" -match '^ROT' })
    if ($rotMods.Count) {
        $rv = "$($rotMods[0].Version)" -replace '^[ve]',''
        Write-Host "  ROT:   v$rv ($($rotMods.Count) modules)" -ForegroundColor Gray
    }
    $navalLoaded = [bool]($Report.Modules | Where-Object { "$($_.Id)" -eq (Get-WarSailsModuleName) })

    Write-Host ""
    Write-Host "  WHAT THIS MEANS:" -ForegroundColor White

    # --- known cause 1: ROT Warsails build without the War Sails DLC (the 2026-07-09 case)
    if ($typ -match 'FileNotFoundException' -and $msg -match 'NavalDLC') {
        Write-Host "  This is the ROT-8-without-War-Sails crash. The installed ROT is the WARSAILS" -ForegroundColor Yellow
        Write-Host "  edition (8.x): at startup it patches the War Sails DLC's code directly, so" -ForegroundColor Yellow
        Write-Host "  without the DLC the game dies before the menu. Their deps are NOT the problem." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  FIX: install ROT 7.1 (the 'ROT 7.1 for Bannerlord 1.3.15' non-Warsails file)" -ForegroundColor Green
        Write-Host "       - that's the build this co-op stack is verified on. (Owning + enabling the" -ForegroundColor Green
        Write-Host "       War Sails DLC would also stop the crash, but 8.x can't co-op with a 7.1 host.)" -ForegroundColor Green
        return
    }
    # --- known cause 2: missing MCM at runtime
    if ($msg -match 'MCM' -or $msg -match 'MCMv\d') {
        Write-Host "  ROT calls MCM (the mod settings menu) at runtime and it isn't installed or is" -ForegroundColor Yellow
        Write-Host "  the wrong version. This crashes ~26s into loading a campaign." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  FIX: menu option 4 (FIX my dependencies) installs the official MCM $(Get-RequiredMcmVersion)." -ForegroundColor Green
        return
    }
    # --- known cause 3: Windows blocked the DLL (Mark of the Web)
    if ($typ -match 'FileLoadException' -or $msg -match '0x80131515|blocked|Operation is not supported') {
        Write-Host "  Windows blocked a mod DLL (files extracted from internet ZIPs get a 'blocked'" -ForegroundColor Yellow
        Write-Host "  tag, and the game then refuses to load them)." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  FIX: menu option 5 (Fix common problems) unblocks every mod DLL automatically." -ForegroundColor Green
        return
    }
    # --- known cause 4: any other missing assembly
    if ($typ -match 'FileNotFoundException' -and $msg -match "assembly '([^',]+)") {
        $asm = $Matches[1]
        Write-Host "  A mod needs the file '$asm.dll' and can't find it - usually a mod that wasn't" -ForegroundColor Yellow
        Write-Host "  fully extracted, or a missing requirement." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  FIX: run menu option 3 (Check my setup) on the machine that crashed - it names" -ForegroundColor Green
        Write-Host "       exactly what's missing or half-installed." -ForegroundColor Green
        return
    }
    # --- fallback: point at the module the exception came from
    if ($src) {
        Write-Host "  The crash came from the module '$src'. I don't recognize the exact cause, but" -ForegroundColor Yellow
        Write-Host "  that's where to look: re-install that mod cleanly (7-Zip, not WinRAR), then run" -ForegroundColor Yellow
        Write-Host "  menu options 3 and 5 on the crashing machine." -ForegroundColor Yellow
    } else {
        Write-Host "  I don't recognize this crash. Run menu options 3 (check) and 5 (fix) on the" -ForegroundColor Yellow
        Write-Host "  crashing machine, and compare setups with option 7 before trying co-op again." -ForegroundColor Yellow
    }
}
