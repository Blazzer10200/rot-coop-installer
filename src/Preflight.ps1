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

    # 2) War Sails OFF
    Chk 'War Sails DLC off' (-not $Game.WarSails) $(if($Game.WarSails){'War Sails is ON - turn off in Steam > Properties > DLC'}else{'off (correct)'})

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

    # 7) Co-op mod present
    $bt = Test-Path (Join-Path $Game.ModulesPath 'BannerlordTogether\bin\Win64_Shipping_Client\BannerlordTogether.dll')
    Chk 'Co-op mod installed' $bt $(if($bt){'present'}else{'BannerlordTogether.dll missing from its bin folder'})

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
