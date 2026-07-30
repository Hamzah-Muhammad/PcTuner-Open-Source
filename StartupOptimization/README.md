# StartupOptimization

**Status: scan + apply + undo, all wired into the UI.** The startup-junk tool of the [PcTuner-Open-Source](../README.md) suite, aimed at **everyday PCs, not gaming rigs** — the toned-down cleaner. Same pattern as FPSOptimization: detect, list every removal as a checkbox. No scan runs automatically — press Scan to check current state vs target (saves a report to `logs\`); Apply fires only after an explicit confirmation modal (creates a System Restore Point first, logs every change for undo); Undo reverts the most recent apply run, whole-run only.

Launch the suite app — see the root [README](../README.md#start-here-the-app). This folder holds the catalog (`manifest.json` + live discovery via `..\changes\PC Startup\Enumerate.ps1`); the UI lives in `..\python\`.

## How it differs from FPSOptimization

The FPS catalog is a **static, verified baseline** (the same 54 checks on every PC). This tool's checklist is a mix:

- **STARTUP APPS** and **LOGON TASKS** are **discovered live at launch** — `..\changes\PC Startup\Enumerate.ps1` enumerates whatever is actually set to start on *this* PC, so those two groups differ on every machine.
- **WINDOWS EXTRAS** turned out to be mostly static, not PC-specific — several of its items (Copilot, `aimgr`, Widgets package/policy, Edge background boost) are the *exact same* checks FPS Optimizer already has, so they come from `manifest.json` and share the canonical script under `..\changes\Windows Changes\` rather than being duplicated.

## What it scans (3 groups)

| Group | Surface | Source | Behavior |
|---|---|---|---|
| **STARTUP APPS** | Registry Run/RunOnce entries (HKCU, HKLM, Wow6432Node) + Startup folder shortcuts (user + common) | `Enumerate.ps1`, live | One checkbox per entry, with its target command shown. Known keeps come annotated and **unchecked** by default |
| **LOGON TASKS** | Logon/boot-triggered scheduled tasks: root-path tasks, Office logon tasks (re-enabled by every Office update), Edge/Google updater tasks | `Enumerate.ps1`, live | Disabled tasks show green ✓ APPLIED; running/ready logon tasks show PENDING. System tasks under `\Microsoft\Windows\*` are never listed |
| **WINDOWS EXTRAS** | The self-starting Windows bloat: Widgets apps + news-feed policy, Copilot, Microsoft AI Manager (`aimgr`), Edge startup boost / background mode, orphaned StartupApproved leftovers | `manifest.json`, static (7 items, shared with FPS Optimizer where identical) | Same checkbox model; each item explains what it removes |

## Keep-list annotations

Known-good entries are recognized and start **unchecked** with a note explaining why:

- **SecurityHealth** (Defender tray) — keep, it's your security status icon.
- **Hardware control** (FanControl, MSI Afterburner) — keep; they set your fan curves / OC at logon.
- Everything else defaults to **checked** (recommended remove) — the "most if not all of them" model. You can uncheck anything before Start.

## Guardrails

- **Nothing changes without Scan → Apply → confirm.** Scan shows current state vs. target only; Apply is a separate, explicitly-confirmed step. Reports are written to `logs\`.
- **Anticheat aware:** kernel anticheat *services* are out of scope here (that's FPSOptimization's domain, with its Manual-never-Disabled rule); only the tray-app Run entry is listed.
- **StartupApproved gotcha handled:** value names can carry trailing spaces — matching is done on exact registry names, not trimmed ones.
- **Drift-aware by design:** vendors re-add their entries on every update; because the catalog is enumerated fresh each launch, whatever came back simply shows up again as PENDING.

## Why a separate tool from FPSOptimization

Startup cleanup is about **boot time, idle RAM, and background processes at logon**; FPSOptimization is about **frame rate while gaming**. They overlap (a lean startup helps FPS), but the decision model differs: startup entries are per-app user choices that change often and need re-auditing after every app update, while the FPS catalog is a mostly-stable system baseline.
