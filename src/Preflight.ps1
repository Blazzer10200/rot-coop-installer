# Preflight.ps1 - the "before you launch" gate.
# Runs every check that predicts a failed load, so the user fixes problems BEFORE
# staring at a loading screen for 20 minutes. Returns GO / NO-GO with plain-English reasons.

function Invoke-Preflight {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Game,
        $Prof = $null
    )
    $checks = [System.Collections.Generic.List[object]]::new()
    function Chk($name,$pass,$detail,$blocker=$true){
        $checks.Add([pscustomobject]@{ Name=$name; Pass=[bool]$pass; Detail=$detail; Blocker=$blocker })
    }

    # 1) Game version
    $verOk = ($Game.VersionNorm -match '^1\.3\.15')
    Chk 'Game version 1.3.15' $verOk $(if($verOk){"OK ($($Game.Version))"}else{"is $($Game.Version) - set to 1.3.15 in Steam > Betas"})

    # 2) War Sails OFF (enabled state, not mere ownership - owning it with the launcher
    #    toggle off is harmless)
    $wsOn = if ($Game.PSObject.Properties['WarSailsEnabled']) { $Game.WarSailsEnabled } else { $Game.WarSails }
    Chk 'War Sails DLC off' (-not $wsOn) $(if($wsOn){'War Sails is ENABLED - turn it off in the launcher Mods tab (or Steam > Properties > DLC)'}else{'off (correct)'})

    # 3) Steam running (the instant-close gotcha)
    $steam = [bool](Get-Process -Name steam -ErrorAction SilentlyContinue)
    Chk 'Steam is running' $steam $(if($steam){'running'}else{'NOT running - start Steam & log in first, or the game closes instantly'})

    # 4) BLSE present
    $blse = Test-Path (Join-Path $Game.BinPath 'Bannerlord.BLSE.LauncherEx.exe')
    Chk 'BLSE launcher installed' $blse $(if($blse){'present'}else{'missing - required to launch modded'})

    # 5) Dependencies (reuse the deep checker if loaded)
    if (Get-Command Test-Dependencies -ErrorAction SilentlyContinue) {
        $deps = Test-Dependencies -Game $Game
        $badDeps = @($deps | Where-Object { $_.State -ne 'OK' -and -not $_.Optional })
        Chk 'Required dependencies OK' ($badDeps.Count -eq 0) $(if($badDeps.Count){"$($badDeps.Count) missing/broken: $(( $badDeps.Name) -join ', ')"}else{'all present'})
    }

    # 6) ROT modules present
    $rot = @(Get-RotModuleNames | Where-Object { Test-Path (Join-Path $Game.ModulesPath "$_\SubModule.xml") })
    Chk 'Realm of Thrones installed' ($rot.Count -ge 3) $(if($rot.Count -ge 3){"$($rot.Count)/4 ROT modules"}else{"only $($rot.Count)/4 ROT modules found"})

    # 6a) ROT VERSION - the check whose absence let a guaranteed-crash setup pass GO.
    #     ROT 8.x (Warsails edition) hard-references the NavalDLC assembly at load: without
    #     the War Sails DLC it dies before the menu, and it can't co-op with a 7.1 host
    #     either way. Verified from a real crash report (2026-07-09).
    if ($rot.Count -ge 1) {
        $wantRot = '7.1'
        if ($Prof -and $Prof.mods.ROT.version) { $wantRot = [string]$Prof.mods.ROT.version }
        $ed = Get-RotEdition -ModulesPath $Game.ModulesPath -WantVersion $wantRot
        $navalPresent = Test-Path (Join-Path $Game.ModulesPath (Get-WarSailsModuleName))
        if ($ed.Match) {
            Chk "ROT version is $wantRot" $true $(if ($ed.GameStamped) { "OK - non-Warsails confirmed via ROT.dll (v$($ed.Version) is the game-version stamp)" } else { "OK (v$($ed.Version))" })
        } elseif ($ed.Edition -eq 'warsails' -and -not $navalPresent) {
            Chk "ROT version is $wantRot" $false "you have ROT v$($ed.Version) - the WARSAILS build - without the War Sails DLC. The game WILL crash before the menu. Install ROT $wantRot (non-Warsails) instead."
        } elseif ($ed.Edition -eq 'warsails') {
            Chk "ROT version is $wantRot" $false "ROT v$($ed.Version) is the Warsails build; this co-op stack is verified on ROT $wantRot (non-Warsails). Install ROT $wantRot."
        } else {
            Chk "ROT version is $wantRot" $false "installed ROT is v$($ed.Version) but this stack needs $wantRot - get the 'ROT $wantRot for Bannerlord 1.3.15' file."
        }
    }

    # 6b) ROT string XML clean? Duplicate <string id> in the GameText files causes the
    #     silent infinite "Initializing new game" loop. Catch it BEFORE launch, not after
    #     20 wasted minutes. (Only checks the two files known to be fatal; cheap scan.)
    $gtFiles = @(
        (Join-Path $Game.ModulesPath 'ROT-Content\ModuleData\comment_strings.xml'),
        (Join-Path $Game.ModulesPath 'ROT-Content\ModuleData\ROT_module_strings.xml')
    ) | Where-Object { Test-Path $_ }
    $dupTotal = 0
    foreach ($gf in $gtFiles) {
        $ids = [regex]::Matches([System.IO.File]::ReadAllText($gf), '<string\s+id\s*=\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
        $dupTotal += @($ids | Group-Object | Where-Object { $_.Count -gt 1 }).Count
    }
    Chk 'ROT text files valid' ($dupTotal -eq 0) $(if($dupTotal -eq 0){'no duplicate keys (good)'}else{"$dupTotal duplicate key(s) - WILL cause the endless loading loop; run 'Fix common problems' (option 5)"})

    # 6c) Windows-blocked DLLs (Mark of the Web): .NET refuses to load a blocked DLL ->
    #     "could not load file or assembly" crashes. Repair unblocks them in one click.
    $blockedDlls = @(Get-BlockedModDlls -Game $Game)
    Chk 'No Windows-blocked DLLs' ($blockedDlls.Count -eq 0) $(if($blockedDlls.Count){"$($blockedDlls.Count) DLL(s) blocked by Windows (downloaded-file tag) - run 'Fix common problems' (option 5) to unblock"}else{'none blocked'})

    # 7) Co-op mod present (+ version vs profile - a mismatch breaks join/desyncs)
    $bt = Test-Path (Join-Path $Game.ModulesPath 'BannerlordTogether\bin\Win64_Shipping_Client\BannerlordTogether.dll')
    Chk 'Co-op mod installed' $bt $(if($bt){'present'}else{'BannerlordTogether.dll missing from its bin folder'})
    if ($bt -and $Prof -and $Prof.mods.BannerlordTogether.version) {
        $btWant = [string]$Prof.mods.BannerlordTogether.version
        $btXml  = Join-Path $Game.ModulesPath 'BannerlordTogether\SubModule.xml'
        $btVer  = if (Test-Path $btXml) { (([regex]::Match((Get-Content $btXml -Raw),'<Version\s*value\s*=\s*"([^"]+)"')).Groups[1].Value) -replace '^[ve]','' } else { $null }
        if ($btVer) {
            Chk "Co-op mod version $btWant" ($btVer -eq $btWant) $(if($btVer -eq $btWant){"OK (v$btVer)"}else{"v$btVer installed, profile expects $btWant - both players must match"}) $false
        }
    }

    # 8) Shader-cache crash risk (warning, not a hard blocker - repair clears it)
    $sack = @(Get-ShaderCachePaths -ModulesPath $Game.ModulesPath | Where-Object { Test-Path $_ })
    Chk 'No stale shader cache' ($sack.Count -eq 0) $(if($sack.Count){"$($sack.Count) precompiled cache(s) present - can cause a crash; run Fix to clear"}else{'clean'}) $false

    $checks
}

function Show-Preflight {
    param([Parameter(Mandatory, ValueFromPipeline)] $Checks)
    begin { $all=[System.Collections.Generic.List[object]]::new() }
    process { foreach($c in $Checks){ $all.Add($c) } }
    end {
        Write-Host ""
        Write-Host "  Pre-launch check" -ForegroundColor Cyan
        Write-Host "  ----------------" -ForegroundColor DarkGray
        foreach ($c in $all) {
            $status = if ($c.Pass) { 'OK' } elseif ($c.Blocker) { 'STOP' } else { 'WARN' }
            Write-Host ("  {0} {1,-26} {2}" -f (Get-StatusIcon $status), $c.Name, $c.Detail) -ForegroundColor (Get-StatusColor $status)
        }
        $blockers = @($all | Where-Object { -not $_.Pass -and $_.Blocker })
        Write-Host ""
        if ($blockers.Count -eq 0) {
            Write-Host "  GO -- everything checks out. Safe to launch." -ForegroundColor Green
        } else {
            Write-Host "  NO-GO -- fix the $($blockers.Count) [STOP] item(s) above first." -ForegroundColor Red
            Write-Host "  (Launching now would very likely crash or hang.)" -ForegroundColor DarkGray
        }
        Write-Host ""
        # return GO/NO-GO for programmatic callers
        [pscustomobject]@{ Go = ($blockers.Count -eq 0); Blockers = $blockers.Count }
    }
}
