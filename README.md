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

## What the menu does

| Option | What it does |
|--------|--------------|
| **1) PLAY** | Runs a pre-launch check, launches the game through BLSE, then opens the live loading screen. The one-button "just let me play." |
| **2) Ready to play?** | Pre-launch check only: version, War Sails, Steam running, BLSE, dependencies, ROT, co-op, shader cache. GO / NO-GO with plain-English reasons. |
| **3) Check my setup** | Deep dependency + install check. For each mod: is the folder there, the manifest valid, the actual DLL in the right `bin` folder, and the version right? |
| **4) Fix common problems** | One-click repair: clears the invalid shader cache (the `0xC0000005` crash), resets a scrambled/all-disabled load order, clears crash markers, checks Steam. Backs up first. |
| **5) Watch the game load** | The friendly loading screen: smooth progress bar + a live "what it's doing now" activity log. Only watches - never touches the game. |
| **6) Co-op: match with a friend** | Host exports their exact setup to a file; friend compares and the tool reports precisely what differs (missing mod / wrong version). Kills the #1 co-op failure. |
| **7) Co-op: how do I start / join?** | Plain-English steps: the host clicks **Host Coop** (not the normal New Campaign button), the friend clicks **Join Co-op**, plus how to connect over the internet. |
| **8) Technical details** | Raw detected info, for troubleshooting. |

## What it does NOT do

- It does **not** download or bundle the mods (licensing). You supply the archives; the tool detects,
  places, validates, repairs, and launches. Every option that needs a download shows the official link.

## Requirements

- Windows 10/11
- Mount & Blade II: Bannerlord (Steam), set to **v1.3.15**, War Sails DLC **off**
- Mod archives: Realm of Thrones 7.1 (1.3.15, non-Warsails), Bannerlord Together, BLSE, and the
  dependency mods (Harmony, UIExtenderEx, ButterLib, MCM)
- 7-Zip recommended (WinRAR corrupts ROT archives)

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
- **`ROT-Map` folder vs `ROT_Map` internal Id** mismatch - detected and reported.
- **Steam not running** -> "Unable to initialize Steam API" instant close - checked before launch.
- **Wrong / incomplete dependencies** - the deep check catches "folder exists but the DLL isn't in bin."

## Project layout

```
Start.bat              double-click launcher (bypasses PowerShell policy prompts)
src/
  ROT-CoopSetup.ps1    entry point + menu
  Detect.ps1           find Bannerlord / version / War Sails
  Dependencies.ps1     deep dependency check + guided fixes
  Validate.ps1         full install diagnose engine
  LoadOrder.ps1        write a correct, dependency-safe load order
  Preflight.ps1        GO / NO-GO pre-launch gate
  FixCrash.ps1         one-click repairs
  ProgressReader.ps1   live loading screen (bar + activity log)
  Launch.ps1           one-click PLAY (preflight -> launch -> watch)
  CoopSync.ps1         export / compare setups between co-op partners
config/
  compat.json          version-compat map + known crashes (keep this updated)
docs/
  DESIGN.md            architecture + roadmap
```

## Roadmap

- [x] Detect, deep dependency check, validate
- [x] One-click crash repair + load-order reset
- [x] **Fix the infinite-loading-screen bug (repair ROT's malformed string XML)**
- [x] Live loading screen (smooth bar + activity log, now detects + warns on the loop bug)
- [x] One-click PLAY (preflight -> launch -> watch)
- [x] Co-op setup export / compare + how-to-start-co-op guide
- [ ] Guided install flow (point at archives -> auto-place everything)
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
