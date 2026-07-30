# PcTuner-Open-Source

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: Windows 11](https://img.shields.io/badge/platform-Windows%2011-0078D6.svg)](#requirements)
[![Latest release](https://img.shields.io/github/v/release/Hamzah-Muhammad/PcTuner-Open-Source)](https://github.com/Hamzah-Muhammad/PcTuner-Open-Source/releases/latest)

A Windows 11 PC-optimization suite: audit first, checkbox consent for every single change, undo logging, and hard guardrails — derived from a real, verified optimization pass on a Ryzen 7 5800X3D + RTX 4070 Ti rig that took Warzone from ~100 to ~200 FPS.

## Table of contents

- [Download](#download)
- [Start here: the app](#start-here-the-app)
- [The tools](#the-tools)
- [Shared principles](#shared-principles-every-tool-in-the-suite)
- [Repo layout](#repo-layout)
- [Requirements](#requirements)
- [Building from source](#building-from-source)
- [License](#license)
- [Disclaimer](#disclaimer)

## Download

Grab the latest release from the **[Releases page](https://github.com/Hamzah-Muhammad/PcTuner-Open-Source/releases/latest)**:

- **`*-win.zip`** — recommended. Unzip anywhere; the `.exe` sits at the top of the extracted folder alongside the sibling folders it needs (`shared/`, `changes/`, `FPSOptimization/`, `StartupOptimization/`). Double-click to run.
- **Bare `.exe`** — only useful if you already have the sibling folders in place (e.g. you cloned the repo). Won't run standalone on its own.

The app self-elevates (UAC prompt) on launch — it needs Administrator rights to read/change the registry, services, and scheduled tasks it audits.

## Start here: the app

A pywebview desktop app (FastAPI backend + React frontend, `python/`) is the suite's front door. Press "Scan PC" on the hub to detect your specs, then launch whichever tool fits the machine. Every tool opens as the same branded checklist — nothing scans automatically, press Scan to check current state vs. target for every item (green ✓ APPLIED for what's already done), then Apply fires only after a confirmation modal (creates a System Restore Point first, logs everything for undo) and Undo reverts the most recent apply run.

## The tools

| Tool | Status | Audience | What it does |
|---|---|---|---|
| **[FPSOptimization](FPSOptimization/)** | **scan + apply + undo, 54-item catalog** | Gaming rigs | All gaming-related FPS changes: telemetry/background-contention elimination, service debloat, NIC power saving, GPU scheduling, filesystem tuning, and the aggressive security trade-offs (mitigations, VBS, Defender scheduling). 54 catalog items across 3 risk levels |
| **[StartupOptimization](StartupOptimization/)** | **scan + apply + undo, dynamic catalog** | Everyday PCs | The toned-down cleaner: dynamically enumerates every Run-key entry, startup-folder shortcut, logon scheduled task, and Windows extra (Widgets, Copilot, Edge preload) that launches itself at logon on *this* PC. Known keeps (security tray, fan/hardware control) start unchecked |

More tools may join the suite (candidates: NetworkOptimization for latency tuning, MaintenanceService for the repeatable cleanups).

## Shared principles (every tool in the suite)

1. **The user sees and approves every change.** Each tool opens with your PC's detected specs and a checkbox per change — uncheck anything before pressing Scan.
2. **Scan before apply, nothing automatic.** Current state vs target is only ever shown after you press Scan; reports saved to the tool's `logs\` folder. Apply requires a second, explicit confirmation.
3. **Everything is reversible.** Old values are logged to undo JSON per run; System Restore point before applying.
4. **Hard guardrails** that no level of aggressiveness crosses: Defender real-time protection stays on, anticheat/launcher services are never Disabled (Manual only), no dangerous Defender exclusions (Temp/roots), `WAN Miniport*` devices never touched, WebView2 security updates keep flowing.
5. **Game-aware:** anything that resets hardware or stops services refuses to run while a game process is active.
6. **Drift-aware:** Windows Updates silently revert many tweaks; each tool's audit mode re-checks its own baseline.

## Repo layout

```
PcTuner-Open-Source/
├── README.md                  ← you are here
├── LICENSE                    ← MIT
├── docs/
│   └── PYTHON_REWRITE_DESIGN.md  ← full architecture/design doc for the Python/React app
├── shared/
│   ├── PrimeChecks.ps1        ← I/O primitives shared by every change script (registry, service,
│   │                             scheduled task, fsutil, power scheme, game-detection, tracked undo)
│   ├── PrimeHeadless.ps1      ← mode-dispatch harness (-Check/-Apply/-Undo -Json) every change
│   │                             script calls into
│   ├── Invoke-SystemScan.ps1  ← "Scan PC" broad inventory (specs + installed software + processes)
│   └── cache\                  (generated, git-ignored)
├── changes/                   ← every individual check/change, one script per item, by sector
│   ├── Windows Changes\        (22 scripts)
│   ├── Services\                (19 scripts)
│   ├── Performance & Hardware\  (14 scripts)
│   └── PC Startup\              (Enumerate.ps1 + 3 parameterized action scripts — dynamic sector)
├── FPSOptimization/            54-item catalog
│   ├── README.md
│   ├── CHANGES.md             ← every change: what / why / exact command / revert
│   ├── manifest.json          ← metadata for all 54 items, pointing at ..\changes\ scripts
│   └── logs\                  (generated, git-ignored)
├── StartupOptimization/        static + live-discovered catalog
│   ├── README.md
│   ├── manifest.json          ← the static items (Windows Extras); dynamic items come from
│   │                             ..\changes\PC Startup\Enumerate.ps1 at launch
│   └── logs\                  (generated, git-ignored)
└── python/                    ← the app: FastAPI backend + React frontend + pywebview launcher
    ├── app.py                  ← desktop entry point (elevation, server, window)
    ├── backend/                ← routes, subprocess bridge to changes\*.ps1, models, reports
    ├── frontend/                ← React SPA (Vite), built to frontend\dist\
    └── PcTuner-Open-Source.spec        ← PyInstaller onefile packaging spec
```

Each catalog item is its own standalone PowerShell script under `changes\`, invoked per-item as a subprocess from the Python backend (via `shared\PrimeHeadless.ps1`'s mode contract) rather than run in-process — isolation over convenience, so one broken/tampered item can only poison its own result. A tool = its `manifest.json` + the shared FastAPI/React app wiring.

## Requirements

Windows 11, WebView2 (preinstalled on Win11), PowerShell 5.1+ (7+ recommended), Administrator elevation (the app self-elevates), and a willingness to reboot for some changes.

## Building from source

```powershell
git clone https://github.com/Hamzah-Muhammad/PcTuner-Open-Source.git
cd PcTuner-Open-Source\python

# Backend
python -m venv .venv
.venv\Scripts\pip install -r requirements.txt

# Frontend (build-time only — the packaged exe never runs Node)
cd frontend
npm install
npm run build
cd ..

# Run in dev mode
.venv\Scripts\python.exe app.py

# Or package a standalone exe (PyInstaller onefile)
.venv\Scripts\pyinstaller PcTuner-Open-Source.spec --noconfirm
```

Packaging spec: `python/PcTuner-Open-Source.spec`. Full architecture/design rationale: `docs/PYTHON_REWRITE_DESIGN.md`.

## License

[MIT](LICENSE) — use, modify, and redistribute freely, including commercially, as long as the copyright notice is kept.

## Disclaimer

Personal tooling, provided as-is, not affiliated with Microsoft. **Use at your own risk — the author is not responsible for any damage to your PC, data loss, or other issues arising from use of this software.** Every change is designed to be reversible (undo logging + a System Restore Point before every apply run — see [Shared principles](#shared-principles-every-tool-in-the-suite)), but no guarantee is made that undo will succeed in every situation. The aggressive tiers deliberately trade security hardening for performance — read each tool's `CHANGES.md` and understand an item before leaving it checked.
