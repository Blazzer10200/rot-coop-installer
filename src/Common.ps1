# Common.ps1 - shared constants + tiny helpers used across the tool.
# Single source of truth for the things that were previously copy-pasted into several
# modules (the ROT module names, the dependency names, the stub-detection test, the
# shader-cache paths). Change them here, everywhere follows.

# Force TLS 1.2 into the allowed protocols. Fresh Windows 10 boxes running PS 5.1 can
# still default .NET to TLS 1.0/1.1, and GitHub refuses those - downloads then die with
# "could not create SSL/TLS secure channel" on OTHER people's machines while working
# fine on an up-to-date one. -bor keeps whatever newer protocols the OS already allows.
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

# ---- Tool settings (persisted per-user, survives tool updates) ----
# Lives in LocalAppData, NOT the tool folder: the tool may sit somewhere read-only
# (Program Files, a zip mounted read-only) and settings must not depend on that.
function Get-ToolSettingsPath { Join-Path $env:LOCALAPPDATA 'rot-coop-tool\settings.json' }

function Get-ToolSettings {
    $p = Get-ToolSettingsPath
    if (Test-Path $p) {
        try { return (Get-Content $p -Raw | ConvertFrom-Json) } catch { }
    }
    $null
}

function Save-ToolSetting {
    param([Parameter(Mandatory)][string] $Name, [Parameter(Mandatory)] $Value)
    $p = Get-ToolSettingsPath
    New-Item -ItemType Directory -Force -Path (Split-Path $p) | Out-Null
    $s = Get-ToolSettings
    if (-not $s) { $s = [pscustomobject]@{} }
    if ($s.PSObject.Properties[$Name]) { $s.$Name = $Value }
    else { $s | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
    [System.IO.File]::WriteAllText($p, ($s | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))
}

# Can we write where the mods live? Steam grants Users write on steamapps, but GOG/Epic
# installs under Program Files often need admin - probe BEFORE a repair half-completes.
function Test-FolderWritable {
    param([Parameter(Mandatory)][string] $Path)
    try {
        $probe = Join-Path $Path ('.rot_write_probe_' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $probe -ErrorAction Stop | Out-Null
        Remove-Item $probe -Force -ErrorAction SilentlyContinue
        $true
    } catch { $false }
}

# Where to tell the user to get game version X - the fix differs per store.
function Get-VersionFixAdvice {
    param($Game, [string] $WantShort = '1.3.15')
    switch ("$($Game.Platform)") {
        'steam' { "set to $WantShort in Steam > right-click the game > Properties > Betas" }
        'gog'   { "install the $WantShort build from GOG (Galaxy: game > settings > Manage installation > Configure > Beta channels, or use the offline installer for $WantShort)" }
        'epic'  { "install the $WantShort build from the Epic Games launcher" }
        'xbox'  { "Game Pass only ships the newest build - if $WantShort isn't offered, this mod stack can't run on the Game Pass copy" }
        default { "install game version $WantShort for your store (Steam: Properties > Betas)" }
    }
}

# The four Realm of Thrones module folders (ROT_Map uses an underscore - it's the
# module's internal Id, and the folder must match it).
function Get-RotModuleNames { @('ROT-Core','ROT-Content','ROT_Map','ROT-Dragon') }

# The BUTR dependency modules ROT relies on. MCM is included: ROT calls it at runtime.
function Get-CoreDepModules { @('Bannerlord.Harmony','Bannerlord.UIExtenderEx','Bannerlord.ButterLib','Bannerlord.MBOptionScreen') }

# The MCM version ROT 7.1 resolves at runtime (assembly 5.11.3.0). Kept as a constant so
# every message/spec agrees.
function Get-RequiredMcmVersion { '5.11.3' }
function Get-McmReleaseUrl      { 'https://github.com/Aragas/Bannerlord.MBOptionScreen/releases/tag/v5.11.3' }

# Is a dependency module folder a ModReady/BetaDeps STUB rather than the official build?
# Stubs ship BetaDeps.*.dll alongside the real DLL; the official builds never do. This is
# the single check that decides "wrong deps -> the endless new-game loop".
function Test-IsStubDep {
    param([Parameter(Mandatory)][string] $ModuleFolder)  # full path to a Modules\<dep> folder
    $bin = Join-Path $ModuleFolder 'bin\Win64_Shipping_Client'
    (Test-Path (Join-Path $bin 'BetaDeps.Foundation.dll')) -or (Test-Path (Join-Path $bin 'BetaDeps.Harmony.dll'))
}

# Do ANY of the installed dependency folders contain stubs? Returns the list of stubbed
# dependency names (empty = all clean).
function Get-StubDeps {
    param([Parameter(Mandatory)][string] $ModulesPath)
    Get-CoreDepModules | Where-Object { Test-IsStubDep (Join-Path $ModulesPath $_) }
}

# ---- ROT version / edition ----
# ROT ships two very different builds for Bannerlord 1.3.15:
#   7.x = the non-Warsails build (what this tool's co-op stack is verified on)
#   8.x = the WARSAILS edition - its OnSubModuleLoad Harmony-patches NavalDLC types, a
#         hard reference to the War Sails DLC assembly. Without the DLC installed the
#         game dies on FileNotFoundException('NavalDLC') before the menu even appears
#         (verified from a real BLSE crash report, 2026-07-09).
# The old detection never read the ROT version at all: modules present + official deps
# all passed GO on a setup that was guaranteed to crash. These helpers close that gap.
function Get-RotVersion {
    param([Parameter(Mandatory)][string] $ModulesPath)
    $xml = Join-Path $ModulesPath 'ROT-Core\SubModule.xml'
    if (-not (Test-Path $xml)) { return $null }
    $v = ([regex]::Match((Get-Content $xml -Raw), '<Version\s*value\s*=\s*"([^"]+)"')).Groups[1].Value
    if ($v) { return ($v -replace '^[ve]','') }
    $null
}

# Probe ROT.dll for the NavalDLC hard reference. Only the Warsails (8.x) build carries
# it (its OnSubModuleLoad patches NavalDLC types); 7.x does not. Assembly reference names
# sit in the .NET metadata as plain text, so a string scan of the DLL is reliable ground
# truth when SubModule.xml can't tell us the edition.
function Test-RotWarsailsDll {
    param([Parameter(Mandatory)][string] $ModulesPath)
    $dll = Join-Path $ModulesPath 'ROT-Core\bin\Win64_Shipping_Client\ROT.dll'
    if (-not (Test-Path $dll)) { return $false }
    [bool](Select-String -LiteralPath $dll -Pattern 'NavalDLC' -Quiet)
}

# Classify the installed ROT against the version the active profile supports.
# Returns: Version (normalized, $null if ROT-Core absent), Edition
# ('non-warsails' | 'warsails' | 'unknown'), GameStamped, SupportedVer, Match (bool).
function Get-RotEdition {
    param(
        [Parameter(Mandatory)][string] $ModulesPath,
        [string] $WantVersion = '7.1'
    )
    $v = Get-RotVersion -ModulesPath $ModulesPath
    $edition = 'unknown'
    $gameStamped = $false
    if ($v -match '^(\d+)') {
        $major = [int]$Matches[1]
        if ($major -ge 8) { $edition = 'warsails' }
        elseif ($major -ge 5) { $edition = 'non-warsails' }
        else {
            # Major < 5 is not a real ROT release number: some ROT uploads stamp the GAME
            # version (e.g. v1.3.15.3) into SubModule.xml instead of the mod version
            # (verified live 2026-07-09: the 7.1-for-1.3.15 file ships v1.3.15.3 while an
            # 8.0.10 install carried its real version). The string can't identify the
            # build, so fall back to the ROT.dll NavalDLC probe - the one difference that
            # actually predicts the crash.
            $gameStamped = $true
            $edition = if (Test-RotWarsailsDll -ModulesPath $ModulesPath) { 'warsails' } else { 'non-warsails' }
        }
    }
    $isMatch = if ($gameStamped) { $edition -eq 'non-warsails' }
               else { [bool]($v -and $v.StartsWith($WantVersion)) }
    [pscustomobject]@{
        Version      = $v
        Edition      = $edition
        GameStamped  = $gameStamped
        SupportedVer = $WantVersion
        Match        = $isMatch
    }
}

# The War Sails DLC's module folder / assembly name (NavalDLC.dll).
function Get-WarSailsModuleName { 'NavalDLC' }

# ---- Windows-blocked DLLs (Mark of the Web) ----
# Files extracted from internet ZIPs carry a Zone.Identifier stream; .NET refuses to
# load a tagged DLL -> assorted "could not load file or assembly" crashes. This is the
# ROT FAQ's #1 fix ("unblock the DLL"), so the tool detects it (and repair unblocks).
function Get-BlockedModDlls {
    param([Parameter(Mandatory)] $Game)
    $roots = [System.Collections.Generic.List[string]]::new()
    foreach ($m in ((Get-RotModuleNames) + (Get-CoreDepModules) + @('BannerlordTogether'))) {
        $b = Join-Path $Game.ModulesPath "$m\bin\Win64_Shipping_Client"
        if (Test-Path $b) { $roots.Add($b) }
    }
    if (Test-Path $Game.BinPath) { $roots.Add($Game.BinPath) }   # BLSE lands here
    $blocked = [System.Collections.Generic.List[string]]::new()
    foreach ($r in $roots) {
        foreach ($dll in (Get-ChildItem $r -Filter *.dll -ErrorAction SilentlyContinue)) {
            if (Get-Item -LiteralPath $dll.FullName -Stream Zone.Identifier -ErrorAction SilentlyContinue) {
                $blocked.Add($dll.FullName)
            }
        }
    }
    $blocked
}

# The ROT shader-cache files whose staleness causes the 0xC0000005 crash.
function Get-ShaderCachePaths {
    param([Parameter(Mandatory)][string] $ModulesPath)
    Get-RotModuleNames | ForEach-Object { Join-Path $ModulesPath "$_\Shaders\D3D11\compressed_shader_cache.sack" }
}

# Bannerlord's ProgramData folder (logs + global shader cache live here).
# $env:ProgramData, not a hardcoded C:\ - Windows can live on any drive.
function Get-BannerlordProgramData { Join-Path $env:ProgramData 'Mount and Blade II Bannerlord' }

# ---- Consistent status presentation (one look across every report) ----
# Severity ladder used everywhere:
#   Green  = fine, nothing to do
#   Red    = will break the game / must fix before playing
#   Yellow = worth fixing but won't stop you playing
# All tags are exactly 6 chars incl. brackets so columns line up across reports.
function Get-StatusIcon([string]$status) {
    switch ($status.ToUpper()) {
        'OK'         { '[ OK ]' }
        'MISSING'    { '[MISS]' }
        'INCOMPLETE' { '[PART]' }
        'BROKEN'     { '[FAIL]' }
        'STUB'       { '[STUB]' }
        'WARN'       { '[WARN]' }
        'STOP'       { '[STOP]' }
        'FIXABLE'    { '[FIX ]' }
        'MISPLACED'  { '[MOVE]' }
        'DIFF'       { '[DIFF]' }
        'EXTRA'      { '[XTRA]' }
        default      { '[ .. ]' }
    }
}
function Get-StatusColor([string]$status) {
    switch ($status.ToUpper()) {
        'OK'         { 'Green' }
        'MISSING'    { 'Red' }     # required thing absent -> won't work
        'INCOMPLETE' { 'Red' }     # required thing half-installed -> won't work
        'BROKEN'     { 'Red' }     # required thing corrupt -> won't work
        'STUB'       { 'Red' }     # wrong deps -> the endless loop
        'STOP'       { 'Red' }
        'WARN'       { 'Yellow' }  # worth fixing, not blocking
        'FIXABLE'    { 'Yellow' }
        'MISPLACED'  { 'Yellow' }
        'DIFF'       { 'Yellow' }
        'EXTRA'      { 'Yellow' }
        default      { 'Gray' }
    }
}
