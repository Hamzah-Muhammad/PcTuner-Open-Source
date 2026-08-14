# FPSOptimization

The gaming-FPS tool of the [PCTuner-Optimization-Tool](../README.md) suite. Detects your PC's specs, lists **54 FPS-related changes as checkboxes** (all pre-checked), and lets you uncheck anything before pressing Start. Covers telemetry and background-contention elimination, service debloat, NIC power saving, GPU scheduling, filesystem tuning, and the aggressive security trade-offs (Spectre mitigations, VBS, Defender scheduling).

> **Status: scan + apply + undo, all wired into the UI.** No scan runs automatically — press Scan to check current state vs target for every checked item (saves a Markdown + JSON report to `logs\`). Apply fires only after an explicit confirmation modal (creates a System Restore Point first, logs every change for undo); Undo reverts the most recent apply run, whole-run only. This folder holds the catalog (`manifest.json` + `..\changes\`); the UI lives in `..\python\`.

## Run it

Launch the suite app — see the root [README](../README.md#start-here-the-app). The window shows:
- **Specs bar** — CPU, GPU, RAM, OS build, disks, active NIC, elevation state
- **Checklist** — grouped by level and module, every item with its id, description, and target state
- **Buttons** — Select all / Select none / Uncheck Level 3 / Scan / Apply / Undo last apply / Open last report

Row colors after a run: 🟢 OK (already at target) · 🟠 WOULD CHANGE (with current value) · 🔵 REVIEW (needs human judgement) · ⚪ skipped (unchecked).

## The three levels

| Level | Name | What it touches | Risk |
|---|---|---|---|
| **1** | Safe | Telemetry, ads/suggestions, 10 bloat scheduled tasks, Edge background containment, NTFS tuning, NIC power saving, USB/PCIe power, mouse acceleration, MMCSS, Hardware-accelerated GPU Scheduling | None — no functionality a gamer uses is lost |
| **2** | Debloat | Background services (with detection guards — e.g. Spooler auto-skips if a printer exists), preinstalled app removal, Widgets, write caching, hibernation, NVIDIA container services (report-only, never auto-disabled) | Low — removes features *some* people use; guarded by detection or prompts |
| **3** | Aggressive | Spectre/Meltdown mitigations OFF, VBS/Memory Integrity OFF, Defender scheduled scans OFF (real-time stays ON), Defender game exclusions, MSI interrupt mode | **Deliberate security trade-offs** — read [CHANGES.md](CHANGES.md) §Level 3 before leaving these checked |

Full catalog with what/why/exact-command/revert for every item: **[CHANGES.md](CHANGES.md)** — including the drift table (what Windows Update silently reverts) and the placebo list (tweaks that measurably do nothing on Windows 11, documented so you don't waste time).

## Scope boundary

FPSOptimization owns changes that affect **frame rate and frame-time consistency while gaming**. Pure startup-entry cleanup (Run keys, startup folders, logon tasks, autostart drift) belongs to the [StartupOptimization](../StartupOptimization/) tool. The one overlap — Edge autolaunch (item 1.8) — stays here because Edge's background presence costs CPU while gaming; StartupOptimization checks the same surface for everyday PCs.

## Files

| File | Role |
|---|---|
| `manifest.json` | The 54 items' metadata (id/level/module/name/desc/target/default-checked/script path) — read directly by the Python backend, no subprocess needed just to render the checklist |
| `..\changes\*\*.ps1` | The actual check/apply/undo scripts, one per item, organized by sector (`Windows Changes`, `Services`, `Performance & Hardware`) — each is invoked as its own subprocess via `..\shared\PrimeHeadless.ps1`'s `-Check`/`-Apply`/`-Undo -Json` contract |
| `CHANGES.md` | Human-readable catalog: what / why / exact implementation / revert per item |
| `logs\` | Generated dry-run reports (`DryRun_<timestamp>.md` + `.json`), git-ignored |

## Honest expectations

The biggest FPS win is eliminating background contention (Levels 1+2 plus closing apps while gaming) — that's the bulk of the reference rig's doubling. VBS off is worth a few percent, mitigations off ~1–3%. After that, a CPU-bound rig sits at its CPU's practical ceiling — the remaining lever is hardware, not registry.
