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
    $shaderTargets = Get-ShaderCachePaths -ModulesPath $Game.ModulesPath
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
        $report.Add("Load order: skipped (config not loaded). Re-run this from the menu (option 5) to reset it.")
    }

    # --- FIX 3: clear crash + safe-mode markers ---
    $markers = @(
        (Join-Path $Game.ModulesPath "Bannerlord.Harmony\session-launching.marker"),
        (Join-Path $env:LOCALAPPDATA "BetaDeps\session-launching.marker")
    )
    $mCount = 0
    foreach ($m in $markers) { if ([System.IO.File]::Exists($m)) { [System.IO.File]::Delete($m); $mCount++ } }
    $report.Add("Crash markers cleared: $mCount (prevents spurious safe-mode prompt)")

    # --- FIX 5: repair ROT's malformed string XML (THE INFINITE-LOOP FIX) ---
    # ROT 7.1 ships GameText string files with DUPLICATE <string id="..."> entries and a
    # couple of empty <tag/> elements. These violate the engine's GameText.xsd schema
    # (id must be unique; tag_name is required). When the engine builds string tables at
    # "Initializing new game", the duplicate-key validation aborts and the whole init
    # retries -- forever. No crash, no error dialog: just an endless load that never
    # reaches the map. This clears it. (Backs up every file it touches.)
    $report.Add((Repair-RotXml -Game $Game -BackupRoot $BackupRoot))

    # --- FIX 6: dependency health (stub deps + missing MCM = the two crash causes) ---
    # These are the deepest ROT co-op failures we hit: (a) ModReady/BetaDeps STUB deps
    # built for the wrong game version -> silent infinite new-game loop; (b) MCM missing
    # -> ROT crashes ~26s in resolving MCMv5. Repair can't safely auto-download, so it
    # reports precisely what to fix.
    foreach ($line in (Test-DepHealth -Game $Game)) { $report.Add($line) }

    # --- CHECK 7: Steam running? (the 'Unable to initialize Steam API' gotcha) ---
    $steam = Get-Process -Name "steam" -ErrorAction SilentlyContinue
    if ($steam) { $report.Add("Steam: RUNNING (good)") }
    else { $report.Add("Steam: NOT RUNNING -- start Steam and log in BEFORE launching, or you get 'Unable to initialize Steam API'") }

    $report
}

# Check the two dependency conditions that silently break a ROT campaign:
#   1) BetaDeps/ModReady STUB libs (built for a different game version) -> new-game loop
#   2) MCM (Bannerlord.MBOptionScreen) missing -> ROT throws resolving MCMv5 ~26s in
# Returns human-readable report lines (does not modify anything).
function Test-DepHealth {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Game)
    $mods = $Game.ModulesPath
    $out  = [System.Collections.Generic.List[string]]::new()

    # stub check across the core dep folders (shared helper - single source of truth)
    $stubHits = @(Get-StubDeps -ModulesPath $mods)
    if ($stubHits.Count -gt 0) {
        $out.Add("DEPENDENCIES: found ModReady/BetaDeps STUB libs ($($stubHits -join ', ')). These reach the menu but can loop forever on a new campaign. Fix it in one click with menu option 4 (FIX my dependencies), or install the official builds manually.")
    } else {
        $out.Add("Dependencies: no stub libs detected (good).")
    }

    # MCM presence (ROT hard-needs it at runtime even though it doesn't declare it)
    $mcmDll = Join-Path $mods 'Bannerlord.MBOptionScreen\bin\Win64_Shipping_Client\MCMv5.dll'
    if (Test-Path $mcmDll) { $out.Add("MCM: present (ROT needs it - good).") }
    else { $out.Add("MCM: MISSING. ROT calls MCMv5 at runtime and will CRASH ~26s into a new game without it. Install official MCM v5.11.3 (github.com/Aragas/Bannerlord.MBOptionScreen/releases/tag/v5.11.3).") }

    $out
}

# Repair ROT's malformed GameText string XML in place. Two defect classes:
#   1) duplicate <string id="..."> within a file -> violates the schema's unique key
#      constraint, which makes campaign init loop forever. We rename repeats to
#      "<id>_dupN" so BOTH strings survive and the id becomes unique.
#   2) empty <tag ... /> with no tag_name -> violates required-attribute. We strip the
#      empty tag element (the surrounding <string> stays valid).
# Only touches GameText-schema files (<strings> root). Skips Languages\ localization
# files, whose <base type="string"> schema legitimately uses <tag language="..."/>.
function Repair-RotXml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Game,
        [string] $BackupRoot = (Join-Path $env:USERPROFILE "Downloads\_rot_installer_backup")
    )
    $rotModules = Get-RotModuleNames
    $filesFixed = 0; $idsFixed = 0; $tagsFixed = 0
    $xmlBackup = Join-Path $BackupRoot "rot_xml"
    New-Item -ItemType Directory -Force -Path $xmlBackup | Out-Null

    foreach ($mod in $rotModules) {
        $md = Join-Path $Game.ModulesPath "$mod\ModuleData"
        if (-not (Test-Path $md)) { continue }
        # GameText string files live directly in ModuleData (NOT under Languages\)
        $xmls = Get-ChildItem $md -Filter '*.xml' -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -notmatch '\\Languages\\' }
        foreach ($xf in $xmls) {
            $raw = [System.IO.File]::ReadAllText($xf.FullName)
            # only GameText-schema files (root <strings>); skip anything else
            if ($raw -notmatch '(?s)<strings\b') { continue }

            $orig = $raw

            # (1) dedupe string ids
            $seen = @{}
            $raw = [regex]::Replace($raw, '(<string\s+id\s*=\s*")([^"]+)(")', {
                param($m)
                $id = $m.Groups[2].Value
                if ($seen.ContainsKey($id)) {
                    $seen[$id]++
                    return $m.Groups[1].Value + ("{0}_dup{1}" -f $id, $seen[$id]) + $m.Groups[3].Value
                } else { $seen[$id] = 0; return $m.Value }
            })
            $thisIds = ($seen.Values | Where-Object { $_ -gt 0 } | Measure-Object -Sum).Sum

            # (2) strip empty <tag .../> elements that have no tag_name (self-closing)
            $emptyTagRx = '(?s)<tag\b(?![^>]*tag_name)[^>]*?/>'
            $thisTags = ([regex]::Matches($raw, $emptyTagRx)).Count
            if ($thisTags -gt 0) { $raw = [regex]::Replace($raw, $emptyTagRx, '') }

            if ($raw -ne $orig) {
                # back up original once
                $rel = $xf.FullName.Substring($Game.ModulesPath.Length).TrimStart('\')
                $bpath = Join-Path $xmlBackup ($rel -replace '[\\/]','__')
                if (-not (Test-Path $bpath)) { [System.IO.File]::WriteAllText($bpath, $orig, [System.Text.UTF8Encoding]::new($false)) }
                [System.IO.File]::WriteAllText($xf.FullName, $raw, [System.Text.UTF8Encoding]::new($false))
                $filesFixed++; $idsFixed += [int]$thisIds; $tagsFixed += [int]$thisTags
            }
        }
    }
    if ($filesFixed -gt 0) {
        "ROT string XML repaired: $filesFixed file(s), $idsFixed duplicate id(s) + $tagsFixed empty tag(s) fixed (THIS is the infinite-load fix; originals backed up)"
    } else {
        "ROT string XML: already clean (no duplicate-key defects found)"
    }
}
