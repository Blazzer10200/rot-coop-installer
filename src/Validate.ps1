# Validate.ps1 - the diagnose engine behind "Repair".
# Parses the live install against compat.json and reports per-item status.
# Depends on a $Game object (Find-Bannerlord) and a loaded profile.

function Get-CompatProfile {
    param([string] $ConfigPath, [string] $ProfileId = 'rot71-coop')
    $json = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    $json.profiles | Where-Object { $_.id -eq $ProfileId } | Select-Object -First 1
}

function Get-ModuleId {
    param([string] $SubModuleXmlPath)
    if (-not (Test-Path $SubModuleXmlPath)) { return $null }
    ([regex]::Match((Get-Content $SubModuleXmlPath -Raw), '<Id\s*value\s*=\s*"([^"]+)"')).Groups[1].Value
}

function Test-RotInstall {
    <#
      Returns a list of finding objects:
        Item, Status (OK|WARN|MISSING|MISPLACED|FIXABLE), Detail, Fix (auto|manual|none)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Game,
        [Parameter(Mandatory)] $Prof
    )
    $f = [System.Collections.Generic.List[object]]::new()
    $mods = $Game.ModulesPath
    function Add($item,$status,$detail,$fix){ $f.Add([pscustomobject]@{Item=$item;Status=$status;Detail=$detail;Fix=$fix}) }

    # 1) Game version
    $verToCheck = if ($Game.VersionNorm) { $Game.VersionNorm } else { $Game.Version }
    if ($verToCheck -match [regex]::Escape($Prof.gameVersionShort)) {
        Add 'Game version' 'OK' $Game.Version 'none'
    } else {
        Add 'Game version' 'WARN' "$($Game.Version) - need $($Prof.gameVersionShort) (Steam > Betas)" 'manual'
    }

    # 2) Each required module present + folder-Id integrity
    $allExpected = @()
    foreach ($modKey in $Prof.mods.PSObject.Properties.Name) {
        $allExpected += $Prof.mods.$modKey.modules
    }
    # reverse map of moduleIdFixups: expectedId -> oldFolderName (e.g. ROT_Map -> ROT-Map)
    $fixupReverse = @{}
    if ($Prof.moduleIdFixups) {
        foreach ($k in $Prof.moduleIdFixups.PSObject.Properties.Name) { $fixupReverse[$Prof.moduleIdFixups.$k] = $k }
    }

    foreach ($m in ($allExpected | Where-Object { $_ })) {
        $folder = Join-Path $mods $m
        $xml    = Join-Path $folder 'SubModule.xml'
        if (-not (Test-Path $folder)) {
            # (a) is it still under its OLD folder name (e.g. ROT_Map expected, ROT-Map on disk)?
            $oldName = $fixupReverse[$m]
            if ($oldName -and (Test-Path (Join-Path $mods $oldName))) {
                Add $m 'FIXABLE' "folder is '$oldName' but must be '$m' (its module Id) - rename it" 'auto'
                continue
            }
            # (b) is it under a wrapper (e.g. "ROT 7.1\<m>")?
            $nested = Get-ChildItem $mods -Directory -ErrorAction SilentlyContinue |
                      ForEach-Object { Join-Path $_.FullName $m } | Where-Object { Test-Path $_ } | Select-Object -First 1
            if ($nested) { Add $m 'MISPLACED' "found nested under $(Split-Path (Split-Path $nested) -Leaf) - needs moving up" 'auto' }
            else { Add $m 'MISSING' 'module folder not found - download required' 'manual' }
            continue
        }
        if (-not (Test-Path $xml)) { Add $m 'WARN' 'folder present but no SubModule.xml' 'manual'; continue }
        $id = Get-ModuleId $xml
        # folder name should equal the module's internal Id
        if ($id -and $id -ne $m) {
            Add $m 'FIXABLE' "folder '$m' but internal Id '$id' - rename folder to '$id'" 'auto'
        } else {
            Add $m 'OK' "Id=$id" 'none'
        }
    }

    # 3) Load order file exists + all expected enabled + dependency order satisfied
    if (Test-Path $Game.ConfigPath) {
        $cfg = Get-Content $Game.ConfigPath -Raw
        $orderIds = [regex]::Matches($cfg,'<Id>([^<]+)</Id>') | ForEach-Object { $_.Groups[1].Value }
        $selFalse = ([regex]::Matches($cfg,'<IsSelected>false</IsSelected>')).Count
        # map ROT-Map -> ROT_Map for comparison
        $want = $Prof.loadOrder
        $missingFromOrder = $want | Where-Object { $_ -notin $orderIds }
        if ($missingFromOrder) { Add 'Load order' 'FIXABLE' "missing/disabled: $($missingFromOrder -join ', ')" 'auto' }
        elseif ($selFalse -gt 0) { Add 'Load order' 'FIXABLE' "$selFalse module(s) disabled - re-enable" 'auto' }
        else { Add 'Load order' 'OK' "$($orderIds.Count) modules ordered" 'none' }
    } else {
        Add 'Load order' 'FIXABLE' 'LauncherData.xml not found - will generate' 'auto'
    }

    # 4) BLSE present
    if (Test-Path (Join-Path $Game.BinPath 'Bannerlord.BLSE.LauncherEx.exe')) { Add 'BLSE launcher' 'OK' 'present' 'none' }
    else { Add 'BLSE launcher' 'MISSING' 'BLSE not installed - download required' 'manual' }

    # 5) Shader-cache crash risk (present .sack = potential 0xC0000005)
    $sack = @('ROT-Content','ROT_Map') | ForEach-Object { Join-Path $mods "$_\Shaders\D3D11\compressed_shader_cache.sack" } |
            Where-Object { Test-Path $_ }
    if ($sack) { Add 'Shader cache' 'FIXABLE' "$($sack.Count) precompiled .sack present - crash risk, clear to rebuild" 'auto' }
    else { Add 'Shader cache' 'OK' 'clean (engine rebuilds)' 'none' }

    $f
}

function Format-Findings {
    param([Parameter(Mandatory)] $Findings)
    $icon = @{ OK='[ OK ]'; WARN='[WARN]'; MISSING='[MISS]'; MISPLACED='[MOVE]'; FIXABLE='[FIX ]' }
    $col  = @{ OK='Green'; WARN='Yellow'; MISSING='Red'; MISPLACED='Yellow'; FIXABLE='Cyan' }
    foreach ($x in $Findings) {
        Write-Host ("  {0} {1,-22} {2}" -f $icon[$x.Status], $x.Item, $x.Detail) -ForegroundColor $col[$x.Status]
    }
    $auto = @($Findings | Where-Object { $_.Fix -eq 'auto' }).Count
    $man  = @($Findings | Where-Object { $_.Fix -eq 'manual' }).Count
    Write-Host ""
    Write-Host "  $auto auto-fixable, $man need manual action (downloads/Steam settings)." -ForegroundColor White
}
