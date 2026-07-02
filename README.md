# ROT Co-op Setup Tool

A Windows helper for installing and repairing **Realm of Thrones 7.1 + Bannerlord Together (co-op)**
on Mount & Blade II: Bannerlord. It automates the fiddly, crash-prone setup that normally takes hours
of guesswork — and includes a **live loading-progress reader** so you never stare at a black screen
wondering if the game froze.

> Built after a real setup where every crash became a feature. This tool exists so you don't repeat it.

## What it does

- **Detects** your Bannerlord install, game version, and War Sails state automatically (Steam library aware).
- **Validates** your mods against a known-good profile — reports per-item: OK / missing / wrong version / misplaced.
- **Repairs** the common failures with one action:
  - Clears the **invalid shader cache** that causes the `0xC0000005` native crash.
  - Resets a **scrambled or all-disabled load order**.
  - Renames the **`ROT-Map` → `ROT_Map`** folder mismatch.
  - Clears crash / safe-mode markers.
  - Checks that **Steam is running** (the "Unable to initialize Steam API" gotcha).
- **Live progress reader** — tails the game's own log and shows a phase-based progress bar
  (booting → mod data → ROT world → campaign gen → map) with a stall warning.

## What it does NOT do

- It does **not** download or bundle the mods (licensing). You supply the archives; it automates placement.
  Links to each official download are provided in-tool.

## Requirements

- Windows 10/11
- Mount & Blade II: Bannerlord (Steam), set to **v1.3.15**, War Sails DLC **off**
- The mod archives: Realm of Thrones 7.1 (1.3.15, non-Warsails), Bannerlord Together, BLSE, ModReady deps
- 7-Zip (the tool checks/installs it — WinRAR corrupts ROT archives)

## Usage

```powershell
# Interactive menu
.\src\ROT-CoopSetup.ps1

# Just watch a load in progress (the progress bar)
.\src\ROT-CoopSetup.ps1 -Watch

# Just run crash repair
.\src\ROT-CoopSetup.ps1 -FixCrash
```

A packaged `.exe` (double-click, no PowerShell policy prompts) is planned — see the roadmap.

## Project layout

```
src/
  ROT-CoopSetup.ps1   entry point + menu
  Detect.ps1          find Bannerlord / version / paths
  Validate.ps1        diagnose engine (powers Repair)
  FixCrash.ps1        the one-click repairs
  ProgressReader.ps1  live loading progress bar
config/
  compat.json         version-compat map + known crashes (the file to keep updated)
docs/
  DESIGN.md           architecture + roadmap
```

## Roadmap

- [x] Detect / Validate / FixCrash / Progress reader (v1 core)
- [ ] Guided install flow (drop archives → auto-place)
- [ ] Package as `.exe` (ps2exe)
- [ ] Co-op "export/import setup" so a friend can match the host exactly
- [ ] WPF GUI (v2)

## Safety

Every destructive step backs up first (to `Downloads\_rot_installer_backup`). The tool is idempotent —
safe to re-run. Nothing is deleted without a backup copy.

## License

MIT — see LICENSE.
