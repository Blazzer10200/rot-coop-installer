# Common.ps1 - shared constants + tiny helpers used across the tool.
# Single source of truth for the things that were previously copy-pasted into several
# modules (the ROT module names, the dependency names, the stub-detection test, the
# shader-cache paths). Change them here, everywhere follows.

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

# The ROT shader-cache files whose staleness causes the 0xC0000005 crash.
function Get-ShaderCachePaths {
    param([Parameter(Mandatory)][string] $ModulesPath)
    Get-RotModuleNames | ForEach-Object { Join-Path $ModulesPath "$_\Shaders\D3D11\compressed_shader_cache.sack" }
}

# Bannerlord's ProgramData folder (logs + global shader cache live here).
function Get-BannerlordProgramData { 'C:\ProgramData\Mount and Blade II Bannerlord' }

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
