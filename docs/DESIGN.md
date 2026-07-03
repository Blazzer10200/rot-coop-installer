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
│             - repair ROT's malformed string XML (dedupe ids) — THE infinite-load fix
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
- **★ Infinite "Initializing new game" loop = duplicate `<string id>` in ROT's GameText XML.** ROT 7.1
  ships `comment_strings.xml` (1 dup + 1 empty `<tag/>`) and `ROT_module_strings.xml` (41 dups) with
  entries that violate `GameText.xsd`'s `string_unique_attribute` unique constraint + required
  `tag_name`. At campaign init the engine builds string tables; the duplicate-key validation aborts and
  the WHOLE init sequence retries — forever. Reaches main menu, then hangs on new-game with NO crash and
  a clean errors log (pure logic loop). Diagnosed from the log: 9,544 iterations / 87 min, loop body =
  string-table load, dies on ROT-Content's two files, never reaches world-gen. **Fix: dedupe the ids
  (`_dupN` suffix, keeps both strings) + strip empty tags.** `str_english.xml` (localization schema,
  `<base type="string">`) also has dups but is loaded via a tolerant path — NOT fatal, but we clean it
  too. Do NOT touch its `<tag language="English"/>` (valid localization syntax).
  **Meta-lesson: this loop looked like "almost done, 95%" by CPU/log-size — the ONLY reliable signal is
  the init-loop COUNTER, not CPU or responsiveness.** The progress reader now counts it and warns.
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
1. [DONE] v1 console script (Detect / Validate / Dependencies / FixCrash / LoadOrder)
2. [DONE] compat.json + validation table
3. [DONE] Progress-reader (smooth bar + live humanized activity log)
4. [DONE] Preflight GO/NO-GO gate + one-click PLAY (launch + watch)
5. [DONE] Friend-sync export/compare
6. [DONE] Published to GitHub (Blazzer10200/rot-coop-installer, MIT)
7. [DONE] Auto-repair dependencies (download official BUTR deps + MCM from GitHub, replace stubs)
8. [DONE] Startup "what should I do next?" recommendation (self-triage for non-technical users)
9. [DONE] VERIFIED end-to-end on a real machine - solo AND co-op both confirmed working
10. [TODO] Guided install flow for the MODS themselves (point at ROT/BLSE archives -> auto-place)
11. [TODO] Package as single .exe (ps2exe)
12. [TODO] v2 WPF GUI wrapper

## Implemented modules (v1, all tested against a real install)
- Detect.ps1         - Steam-library-aware install/version/War Sails detection
- Dependencies.ps1   - deep check (folder + manifest + DLL-in-bin + version + STUB detection) w/ guided fixes
- Validate.ps1       - full install diagnose table
- LoadOrder.ps1      - writes correct dependency-safe LauncherData.xml (fixes rescramble)
- Preflight.ps1      - GO/NO-GO pre-launch gate (incl. ROT-text-files + dep-health checks)
- FixCrash.ps1       - shader-cache clear, load-order reset, ROT-XML repair, dep-health, Steam check
- FixDependencies.ps1- auto-download + install official Harmony/ButterLib/UIExtenderEx/MCM from GitHub
- ProgressReader.ps1 - live loading screen: smooth bar + rolling humanized activity feed
- Launch.ps1         - one-click PLAY: preflight -> BLSE launch -> watch
- CoopSync.ps1       - export/compare setup fingerprints between co-op partners
- ROT-CoopSetup.ps1  - menu entry point + startup recommendation (guarded so importing doesn't auto-run)

## Engineering notes / gotchas baked in
- ASCII-only output (PS 5.1 console encoding mangles em-dashes / box-art into mojibake).
- Progress bar ratchets forward only (Bannerlord loads in overlapping waves; raw phase
  detection would jump backwards and scare users).
- Bar is size-driven for smoothness; "Initializing new game" loop => treat as ~95%+.
- Entry point guarded via $MyInvocation.InvocationName so dot-sourcing imports functions
  without launching the menu.
- $Profile is a reserved automatic var - profile params are named $Prof.
- Version strings carry a leading 'v'; Format-Ver normalizes to avoid 'vv2.10' display bugs.
