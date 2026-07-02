---
title: ROT Co-op Installer — Design Spec
tags: [design, gaming, bannerlord, tool]
status: draft
updated: 2026-07-02
---

# Realm of Thrones Co-op Installer — Design Spec

**Goal:** One tool that turns the multi-hour manual ROT + Bannerlord Together co-op setup into a guided,
crash-proof install. Windows-first. Born from a real setup where every crash = a feature.

## Positioning (the gap)
Existing tools only *sort load order* (Nexus 11547, moddingtools). Vortex is generic. Install guides are
manual + failing ("watched countless videos, no luck"). **Nobody does a ROT-specific installer that also
fixes the crashes.** That's the niche.

## Guiding principles
1. **Don't bundle mods** (licensing). User supplies the archives; tool automates everything else.
2. **Fix > document.** Every crash the user hit becomes a one-click fix, not a wiki paragraph.
3. **Idempotent + reversible.** Re-runnable safely; every destructive step backs up first.
4. **Explain, don't just do.** Each step prints what/why so users learn + trust it.

## Architecture (v1 = console PS script → v2 = WPF GUI)

```
ROT-CoopSetup.ps1
├─ DETECT     parse libraryfolders.vdf → Bannerlord path, version, War Sails state
├─ PRECHECK   assert v1.3.15 + War Sails OFF; else print exact Steam fix steps
├─ ACQUIRE    prompt user to drop: ROT.7z, BannerlordTogether.zip, BLSE.7z, deps bundle
│             (link each Nexus/ModDB page; verify 7z signature before trusting)
├─ INSTALL    extract → Modules\; strip wrapper folders; rename ROT-Map→ROT_Map
│             BLSE bin→game bin; co-op DLL→bin\Win64_Shipping_Client
├─ LOADORDER  generate LauncherData.xml (deps→ROT→co-op, GameType=Singleplayer, all IsSelected)
├─ VALIDATE   parse every SubModule.xml; confirm each DependedModule resolves earlier; green/red table
├─ FIXCRASH   ★ THE KILLER FEATURE ★
│             - delete ROT *.sack shader caches (the 0xC0000005 fix)
│             - reset scrambled/all-false load order
│             - clear BLSE crash + safe-mode markers
│             - verify Steam is running (the "Steam API init" gotcha)
├─ SHORTCUT   desktop link → BLSE LauncherEx
└─ LAUNCH     start BLSE
```

## The compat map (the one file to maintain)
`compat.json` — single source of truth, updated as mods evolve:
```json
{
  "profiles": [{
    "name": "ROT 7.1 + Co-op",
    "gameVersion": "1.3.15.110062",
    "warSails": false,
    "mods": {
      "ROT": {"version":"7.1","modules":["ROT-Core","ROT-Content","ROT_Map","ROT-Dragon"],
              "source":"nexus/2907","notes":"non-Warsails build only"},
      "BannerlordTogether":{"version":"0.4.1","source":"nexus/10426"},
      "BLSE":{"version":"1.6.7+","source":"nexus/1"},
      "deps":{"bundle":"ModReady","source":"nexus/11274",
              "note":"stubs REACH MENU; do NOT swap for official BUTR (ButterLib needs BLSE.AssemblyResolver → crashes)"}
    },
    "loadOrder":["Native","SandBoxCore","Sandbox","StoryMode","CustomBattle",
                 "Bannerlord.Harmony","Bannerlord.UIExtenderEx","Bannerlord.ButterLib","Bannerlord.MBOptionScreen",
                 "ROT-Core","ROT-Content","ROT_Map","ROT-Dragon","BannerlordTogether"]
  }]
}
```

## Hard-won gotchas to bake in (from the real setup)
- **ROT-Map folder Id = `ROT_Map`** (underscore) — rename folder or dep resolution fails.
- **Shader cache `.sack` = crash** — mismatched precompiled shaders → native 0xC0000005. Delete them.
- **Steam must be running + logged in** first → else "Unable to initialize Steam API" instant-close.
- **Launcher rescrambles LauncherData.xml** if user touches Mods tab (can set all IsSelected=false).
- **ROT 7.1 not 8.0** — 8.0 needs War Sails ON, conflicts with co-op.
- **First campaign gen is slow** (data-load + world-gen) — tool should show a live-log progress reader
  (tail rgl_log, surface phase) so users don't kill a working load.
- **Safe-mode + crash-upload prompts after a crash** → click No.
- **7-Zip required** (WinRAR corrupts ROT) — tool checks/installs via winget.

## Co-op friend-sync feature (v1.5)
"Export my setup" → hashes of each mod + versions + load order → shareable file.
Friend runs "Import + verify" → tool confirms their install matches host exactly (the #1 co-op failure:
mismatched versions). Steam networking = no port-forward, so networking is a non-issue.

## Progress-reader (nice-to-have, high value)
Tail `C:\ProgramData\Mount and Blade II Bannerlord\logs\rgl_log_*.txt` during load; map phases
(data-load → world-gen → map) to a text progress bar. Solves the "black screen, no progress" pain directly.

## Build order
1. v1 console script (DETECT→FIXCRASH proven; reuse tonight's PowerShell verbatim)
2. compat.json + validation table
3. Progress-reader
4. v1.5 friend-sync export/import
5. v2 WPF GUI wrapper
6. Distribute as Nexus tool + GitHub (open-source builds trust for a "runs .exe on your game" tool)
