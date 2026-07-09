# ROT Co-op Setup Tool

A Windows helper for installing, repairing, and **launching** the
**Realm of Thrones 7.1 + Bannerlord Together (co-op)** setup on Mount & Blade II: Bannerlord.

It automates the fiddly, crash-prone setup that normally eats hours of guesswork, and gives you a
**friendly live loading screen** (with a real activity log) so you never stare at a black screen
wondering if the game froze.

> Built from a real, painful setup where every crash became a feature. This tool exists so nobody
> else has to go through that.

## Just want to use it?

1. Download this project (green **Code** button > **Download ZIP**) and **extract the whole folder**.
2. Double-click **`Start.bat`**.
3. Pick an option from the menu. That's it - no PowerShell knowledge needed.

When you open the tool it **scans your setup and tells you the one thing to do next** in plain
English - so you don't have to know which option to pick. Then:

## What the menu does

| Option | What it does |
|--------|--------------|
| **1) PLAY** | Runs a pre-launch check, launches the game through BLSE, then opens the live loading screen. The one-button "just let me play." |
| **2) Am I ready to play?** | Pre-launch check only: version, War Sails, Steam running, BLSE, dependencies, ROT, co-op, shader cache, ROT text files. GO / NO-GO with plain-English reasons. |
| **3) Check my setup** | Deep dependency + install check. For each mod: is the folder there, the manifest valid, the actual DLL in the right `bin` folder, the version right, and is it the **official** build (not a stub)? |
| **4) FIX my dependencies** | **The big one.** Automatically downloads the *correct, official* Harmony, ButterLib, UIExtenderEx, MCM **and BLSE itself** (the versions ROT needs) straight from GitHub, and replaces any wrong "stub" copies. This is the one-click fix for the game looping forever on a new campaign. Backs up first; game must be closed. |
| **5) Fix common problems** | Repairs the invalid shader cache (the `0xC0000005` crash), renames wrongly-named module folders (`ROT-Map` → `ROT_Map`), resets a scrambled/all-disabled load order, repairs ROT's malformed text files, checks dependency health + MCM, clears crash markers, checks Steam (Steam copies only). Backs up first. |
| **6) Co-op: how do I start / join?** | Plain-English steps: the host clicks **Host Coop** (not the normal New Campaign button), the friend clicks **Join Co-op**, plus how to connect over the internet. |
| **7) Co-op: match with a friend** | Host exports their exact setup to a file; friend compares and the tool reports precisely what differs (missing mod / wrong version / stub deps). Kills the #1 co-op failure. |
| **8) Watch the game load** | The friendly loading screen: smooth progress bar + a live "what it's doing now" activity log. Recognizes the healthy first-load (terrain building) and warns if it detects the endless loop. Only watches - never touches the game. |
| **9) Technical details** | Raw detected info, for troubleshooting. |
| **10) Read a crash report** | Point it at the `.zip` BLSE offers to save when the game dies (yours **or a friend's**) and it explains the crash in plain English + matches it against every known cause. No more eyeballing JSON. |

## What it does NOT do

- It does **not** download or bundle the *content mods themselves* - Realm of Thrones and
  Bannerlord Together (licensing). You supply those; every option that needs one shows the
  official link.
- It **does** download the free, open-source pieces with official public GitHub releases:
  **BLSE** (the launcher) and the **dependency libraries** (Harmony, ButterLib, UIExtenderEx,
  MCM) - because getting the wrong version of those is the single most common way this
  setup breaks.

## Requirements

- Windows 10/11
- Mount & Blade II: Bannerlord set to **v1.3.15**, War Sails DLC **off**.
  **Steam, GOG, Epic, and Xbox/Game Pass installs are all auto-detected** (any drive, every
  Steam library folder). Game somewhere unusual? The tool asks for the folder once and
  remembers it.
- Mod archives: Realm of Thrones 7.1 (1.3.15, non-Warsails) and Bannerlord Together.
  BLSE and the dependency mods are downloaded automatically (option 4).
- 7-Zip (needed for the automatic downloads; WinRAR corrupts ROT archives)

## The crashes this tool fixes (learned the hard way)

- **The infinite loading screen (the big one).** Two separate causes both produce the same endless
  load - reach the main menu fine, then the "new campaign" loading screen never ends, no crash, no
  error message:
  1. **Wrong-version dependency stubs.** The popular "ModReady"/BetaDeps bundle ships *stub* copies of
     Harmony/ButterLib/UIExtenderEx built for a **different game version**. They load and reach the
     menu, but their patches silently fail at campaign start, so the game re-initializes forever. The
     fix is to use the **official** BUTR dependencies that match your game version. The tool detects
     these stubs and tells you exactly what to replace.
  2. **Malformed ROT text files.** ROT 7.1 ships a few string files with **duplicate entry IDs** and
     empty tags that break the game's schema rules. The tool repairs them (backing them up first).
- **The ~26-second crash into a new game.** ROT secretly needs **MCM** (the mod settings menu) at
  runtime - it calls into it even though it doesn't list it as a requirement, so nothing warns you.
  Without MCM you crash about 26 seconds into loading a campaign. The tool checks for it and points
  you at the correct official version (v5.11.3).
- **Invalid shader cache** -> native `0xC0000005` crash. The tool clears the stale `.sack` files so the
  engine rebuilds them cleanly.
- **Scrambled load order / everything disabled** - the launcher silently rewrites `LauncherData.xml`;
  the tool resets it to a correct, dependency-safe order.
- **`ROT-Map` folder vs `ROT_Map` internal Id** mismatch - detected, and **renamed automatically**
  by Fix common problems.
- **Steam not running** -> "Unable to initialize Steam API" instant close - checked before launch
  (Steam copies only; GOG/Epic/Game Pass copies skip this check).
- **Wrong / incomplete dependencies** - the deep check catches "folder exists but the DLL isn't in bin."
- **Wrong ROT build (8.x Warsails).** ROT 8.x hard-references the **War Sails DLC** (`NavalDLC`) at
  startup: without the DLC it crashes with `FileNotFoundException: NavalDLC` **before the menu**, and
  it can't co-op with a 7.1 host regardless. Every dependency can be perfect and it still dies -
  which is exactly how it slipped past the old checks (real incident, 2026-07-09). The tool now reads
  the installed ROT version everywhere: status header, preflight, deep check, and startup advice.
- **Windows-blocked DLLs (Mark of the Web).** DLLs extracted from internet ZIPs carry a "blocked"
  tag that stops .NET loading them -> "could not load file or assembly". Preflight detects them;
  Fix common problems unblocks them all in one pass.

## Project layout

```
Start.bat              double-click launcher (bypasses PowerShell policy prompts)
src/
  ROT-CoopSetup.ps1    entry point + menu + "what should I do next?" recommendation
  Common.ps1           shared constants + helpers (module lists, stub detection, status styling,
                       tool settings, TLS setup, writability probe)
  Detect.ps1           find Bannerlord on Steam / GOG / Epic / Game Pass / custom path
  Dependencies.ps1     deep dependency check (incl. stub detection) + guided fixes
  Validate.ps1         full install diagnose engine
  LoadOrder.ps1        write a correct, dependency-safe load order
  Preflight.ps1        GO / NO-GO pre-launch gate
  FixCrash.ps1         one-click repairs (shader cache, load order, text files, dep health)
  FixDependencies.ps1  auto-download + install the official deps (the headline repair)
  ProgressReader.ps1   live loading screen (bar + activity log)
  Launch.ps1           one-click PLAY (preflight -> launch -> watch)
  CoopSync.ps1         export / compare setups between co-op partners
  CrashReport.ps1      read a BLSE crash report zip + explain it (matches known causes)
config/
  compat.json          version-compat map + known crashes (keep this updated)
docs/
  DESIGN.md            architecture + roadmap
```

## Roadmap

- [x] Detect, deep dependency check (incl. stub detection), validate
- [x] One-click crash repair + load-order reset
- [x] **Fix the infinite-loading-screen bug** (both causes: wrong-version stub deps + malformed text files)
- [x] **Auto-download + install the correct official dependencies** (the headline repair)
- [x] "What should I do next?" recommendation on startup (guides non-technical users)
- [x] Live loading screen (recognizes healthy first-load, warns on the loop bug)
- [x] One-click PLAY (preflight -> launch -> watch)
- [x] Co-op setup export / compare + how-to-start-co-op guide
- [x] **Verified end-to-end on a real machine: solo + co-op both confirmed working**
- [x] ROT build/edition detection (8.x Warsails vs 7.1) - closes the gap a real crash exposed
  (handles builds that stamp the *game* version into SubModule.xml via a `ROT.dll` probe)
- [x] Windows-blocked-DLL (Mark of the Web) detection + one-click unblock
- [x] Crash-report reader: drop in a BLSE `.zip`, get a plain-English diagnosis
- [x] **Runs on other people's machines**: Steam (registry + every library) / GOG / Epic /
  Xbox Game Pass detection, manual game-folder fallback (remembered), store-aware advice,
  TLS 1.2 + IE-free downloads for stock PS 5.1, write-permission probe with a plain
  "run as administrator" fix, no hardcoded `C:\` paths, OneDrive-safe Desktop export
- [x] **BLSE auto-install** from the official GitHub release (was the last manual download
  that had no auto path)
- [x] Auto-rename module folders whose name doesn't match their internal Id (`ROT-Map` -> `ROT_Map`)
- [x] Profile picker scaffolding: ship a second verified stack in `compat.json` and the tool
  offers the choice - no code changes needed
- [ ] Guided install flow for the mods themselves (point at ROT archives -> auto-place)
- [ ] Package as a single `.exe` (ps2exe)
- [ ] WPF GUI

## Safety

Every destructive step backs up first (to `Downloads\_rot_installer_backup`). The tool is idempotent -
safe to re-run - and nothing is deleted without a backup copy. It only ever reads the game's log; it
never modifies a running game.

## Compatibility note

Mod versions drift over time. If a future ROT or Bannerlord Together update changes the working
version combo, update `config/compat.json` - that one file is the source of truth.

## License

MIT (see LICENSE). Unofficial fan tool; not affiliated with TaleWorlds, the Realm of Thrones team,
the Bannerlord Together team, or BUTR. Does not distribute any mod files.
