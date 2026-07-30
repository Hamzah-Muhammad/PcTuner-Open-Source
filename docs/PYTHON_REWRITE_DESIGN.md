# PcTuner-Open-Source — Python Rewrite: Structure & Design (v2 planning doc)

Status: **approved 2026-07-19 — decisions locked, no Python code written yet.**
Scope: replace the PowerShell/WPF UI layer with a FastAPI + pywebview app,
while keeping the proven PowerShell check catalogs as the scan engine.

## 0. Decisions (confirmed 2026-07-19)

1. **Process model:** single pywebview window, client-side SPA routing
   between hub and tool views. One elevated Python process for the whole
   app — no per-tool sibling processes, no `pwsh.exe`-resolution code.
2. **Bridge approach:** subprocess + JSON over stdout to the existing
   PowerShell catalogs is the **permanent** architecture, not a migration
   shim. PowerShell stays the check engine indefinitely.
3. **Old PS entry points:** kept indefinitely as a standalone/no-Python
   fallback (`PrimePCTuner.ps1`, `Start-FPSOptimization.ps1`,
   `Start-StartupOptimization.ps1`) — nothing gets retired.
4. **Report location:** scan reports keep writing to the existing
   `FPSOptimization\logs` / `StartupOptimization\logs` folders — same
   history, whether triggered from PS-standalone or Python.
5. **One change, one script (confirmed 2026-07-19, changes the original
   draft of §3):** the shared `Catalog.ps1` per tool is replaced by
   individual `.ps1` files per change, invoked individually by Python —
   never grouped/batched together — for isolation, auditability, and
   future per-script allowlisting/signing. FPS's 52 static checks split
   1:1 into 52 files; Startup's dynamic catalog splits by action type
   (4 parameterized scripts) since its items aren't known ahead of time.
   Full design in §3, §5.5, §8.5.

## 1. Recap of the decision already on record

- FastAPI backend, shelling out to individual per-change PowerShell scripts
  via subprocess (§0 #5, §3), reading the JSON each one emits.
- pywebview + HTML/CSS frontend, pixel-matching the current dark/green
  Prime theme.
- Packaged with PyInstaller (more mature single-file exe story than ps2exe).
- Written and reviewed **before** any Python code.

## 2. Why keep PowerShell as the engine (not reimplement checks in Python)

The 52 FPS checks + the fully dynamic Startup catalog are proven and already
debugged (registry reads, `Get-CimInstance`, scheduled tasks, `powercfg`,
`fsutil`). Porting all of that to Python would mean `pywin32`/`wmi` calls
that are strictly worse for touching Windows-native surfaces, for no
behavioral gain — pure risk of regressions with zero user-visible benefit.
Python's job in this rewrite is orchestration, UI, and packaging — not
re-deriving `Test-RegValue`/`Test-ServiceStartMode` in a different language.

## 3. Gap to close: today's engine is one big file per tool, and welded to the WPF UI

Two problems being solved together here, both requiring the same underlying
split:

1. `Invoke-PrimeScan` in `shared\PrimeUI.ps1` updates live WPF row objects
   while it scans — catalog evaluation and UI painting are one function.
   That has to be split before anything can be driven headlessly.
2. **(Decided 2026-07-19, changes the earlier draft of this section):**
   each individual change gets its **own standalone `.ps1` file**, invoked
   individually by Python — not one shared `Catalog.ps1` looping over 52
   in-process scriptblocks. This is a deliberate choice for isolation and
   auditability, not a performance optimization (see the concurrency
   note in §5.5 for the cost this introduces and how it's absorbed):
   - Each script is small enough to read in one sitting and reason about
     in isolation — reviewing "does item 1.5 do something unexpected"
     never requires reading a 500-line shared file.
   - A bug or bad edit in one script's `Apply` logic can't reach code it
     has no reference to, the way a shared-scope catalog file always
     risks.
   - It opens the door to **per-script allowlisting later** — Python could
     hash-pin the exact set of approved scripts and refuse to invoke
     anything that doesn't match, which is only practical at this
     granularity (a hash over one 500-line shared file tells you "the
     whole catalog changed," not "which one item changed"). Not built in
     v1, but the file layout is what makes it possible later.
   - Low-level I/O primitives (`Test-RegValue`, `Set-RegValueTracked`,
     `Test-ServiceStartMode`, …) stay in a **shared** helper library —
     duplicating registry get/set plumbing into 50+ files would be *more*
     risk surface, not less. What's isolated per-file is the **policy**
     (which path, which value, which target) — that's the part actually
     worth auditing per-change.

### Storage: by sector, not by tool (user-directed, confirmed 2026-07-19)

Reading the full existing catalogs revealed that Startup Optimizer's items
aren't uniformly dynamic: **Run keys, startup-folder shortcuts, and logon
scheduled tasks are genuinely PC-specific** (discovered live, vary per
machine), but its "Windows Extras" (`W.1`-`W.5`) and "Leftover Toggles"
(`X.1`) modules are **static, known-ahead-of-time checks** — several of
them (Remove Copilot, Remove aimgr, Remove Widgets, Edge boost/background
off) are near-duplicates of items already in FPS's own catalog. That
changes the split: individual scripts are stored **by topic/sector**, not
nested under whichever "tool" folder they historically lived in, and
genuine duplicates across the two old catalogs get merged into one
canonical script. Four sectors (confirmed):

- **Windows Changes** — registry/policy tweaks + bloat-app removal.
- **PC Startup** — the genuinely dynamic startup surface.
- **Services** — service start-mode changes (big enough alone: 19 items).
- **Performance & Hardware** — filesystem/NIC/power tuning.

Physical layout: `changes\<Sector>\<Id>_<Slug>.ps1` at the repo root, not
nested under `FPSOptimization\`/`StartupOptimization\` — those folders
keep their tool-level content (entry-point script, `logs\`, `README.md`,
`CHANGES.md`) but no longer own the check scripts directly. A tool's
"catalog" is now a *view* over sector folders, defined by its
`manifest.json` (§0 #5, updated): each entry's `Script` field is a
sector-relative path (e.g. `Services\DiagTrack.ps1`), so which sector a
file physically lives in is fully decoupled from which tool's checklist it
appears under in the UI — including the same script appearing in *both*
tools' manifests where a genuine duplicate was merged.

### Windows Changes — static, splits 1:1 (with cross-catalog dedup)

FPS's Telemetry & Privacy (7), Bloat Scheduled Tasks (1), Edge Containment
(3), Apps (4), Security Trade-offs (5) = 20 items, plus Startup's Windows
Extras/Leftover Toggles (6) — minus the ~5 that duplicate an FPS item
(Copilot removal, aimgr removal, Widgets package removal, Widgets policy,
Edge boost/background) — merged to one script each, referenced from both
tools' manifests. Each script:
- Dot-sources `shared\PrimeChecks.ps1` (I/O primitives) and
  `shared\PrimeHeadless.ps1` (mode-dispatch/JSON-output plumbing, no
  WPF/elevation).
- Implements exactly one item's `-Check -Json`, `-Apply -Json`, and
  `-Undo -Json -PreviousValueJson <json>` modes.
- ~15–30 lines: dot-source, call the shared primitive with this item's
  specific path/name/value, switch on mode, print JSON.

### Services, Performance & Hardware — same static 1:1 split

19 files under `changes\Services\` (2S.1-2S.19), 13 under `changes\
Performance & Hardware\` (1.11-1.13, 1.14-1.15, 1.16-1.19, 2B.1-2B.4) —
same shape as Windows Changes' scripts, one file per item.

### PC Startup — dynamic, splits by action type, not by instance

The only sector where items genuinely aren't known ahead of time — which
Run-key entries or scheduled tasks exist depends on what's actually
installed on *this* PC, discovered live at scan time. The same isolation
principle applies at the only granularity a dynamic catalog allows: **one
script per action type**, parameterized per discovered instance:
- `changes\PC Startup\Enumerate.ps1 -Json` — the discovery step (replaces
  today's dynamic-catalog-build logic). Lists everything currently on this
  PC across the 3 dynamic categories below, with enough identifying detail
  (registry path+name, file path, task path+name) for Python to know what
  to pass to the action scripts. Plays the same "fast, single-call
  listing" role the static sectors' `manifest.json` files play — except it
  has to actually run (it's PC-specific), so it's one subprocess call, not
  a static read.
- `changes\PC Startup\RunKeyEntry.ps1 -RegPath ... -ValueName ...
  -Check|-Apply|-Undo -Json`
- `changes\PC Startup\StartupFolderShortcut.ps1 -FilePath ...
  -Check|-Apply|-Undo -Json` (Apply backs up the file before deleting it,
  per §8.5 — unchanged by this split)
- `changes\PC Startup\ScheduledTask.ps1 -TaskPath ... -TaskName ...
  -Check|-Apply|-Undo -Json`

(The old `WindowsExtra.ps1` from the previous draft of this section is
gone — those items turned out to be static, so they moved into Windows
Changes above instead of staying a 4th parameterized action script here.)

### Consequence for the existing WPF app (still kept indefinitely, §0 #3)

`Invoke-PrimeScan`/`New-PrimeChecklistApp` currently dot-source one
`Catalog.ps1` and run checks **in-process** as scriptblocks. With the
catalog logic moved into standalone per-change scripts, the WPF app has to
shell out to them too — the same subprocess-per-item pattern Python uses,
not a second, duplicate in-process copy of the same logic (that would
recreate exactly the "grouped together" problem this whole change is
solving, just in a second place). This is a real, contained change to
`PrimeUI.ps1`'s scan loop, not a cosmetic one — flagging it now so it's
expected work when §3 gets implemented, not a surprise. The WPF app is
still "kept indefinitely" per §0 #3; its internal plumbing just becomes
consistent with the new architecture instead of forking from it.

**Headless entry points still exist per tool, but now they're thin
dispatchers to individual scripts, not scan runners themselves:**
```
Start-FPSOptimization.ps1 -Headless -Check -Json -Id "1.1"
Start-FPSOptimization.ps1 -Headless -Apply -Json -Id "1.1"
Start-FPSOptimization.ps1 -Headless -Undo  -Json -Id "1.1" -PreviousValueJson '...'
```
(In practice Python's `ps_bridge.py` can invoke the manifest's `Script`
path (`changes\<Sector>\<Id>_<Slug>.ps1`) directly — the entry-point
wrapper above is a convenience/stable-CLI-surface layer, not a required
hop.)

## 3.5 Elevation flow (Python side)

Mirrors `Invoke-PrimeBootstrap`'s behavior, adapted for a single-elevation-
at-startup model (no per-tool relaunch, no STA/WPF concerns).

1. On `app.py` start — before the uvicorn thread starts or the pywebview
   window opens — check `ctypes.windll.shell32.IsUserAnAdmin()`.
2. If not elevated, relaunch self via `ShellExecuteW(None, "runas", target,
   params, None, 1)`:
   - Frozen (PyInstaller onefile): `target = sys.executable` (the exe
     itself).
   - Dev mode: `target = sys.executable` (python.exe), `params` includes
     the script path — same frozen-vs-dev dual resolution as PS's
     `$PSScriptRoot` fallback (§3), just the Python version of it.
   - On success: `sys.exit(0)` immediately — the elevated child is now the
     real app.
   - On decline/failure (`ShellExecuteW` returns an error handle, e.g. the
     user clicked "No" on the UAC prompt): **do not exit** — warn and
     continue unelevated, exactly like PS's try/catch-and-continue. The app
     still opens; some scan items will read REVIEW/ERROR instead of a clean
     result, which is already how the PS app behaves today under the same
     condition.
3. A `--self-test` flag (Python's equivalent of `-SelfTest`) skips
   elevation entirely, for CI/verification runs that must not trigger UAC.
4. **No STA/WPF-equivalent relaunch is needed.** That check in
   `Invoke-PrimeBootstrap` exists only because WPF requires an STA thread;
   pywebview has its own threading contract (window creation on the main
   thread), already satisfied by construction — uvicorn runs in a
   background thread, `webview.start()` runs on main.
5. **Key guarantee this whole model leans on:** once `app.py` is running
   elevated, every `subprocess.run([ps_exe, ...])` child inherits that
   elevation token automatically — Windows duplicates the parent's token on
   process creation unless told otherwise. This is exactly why the PS-side
   headless bootstrap can skip self-elevation (§3), and why today's WPF hub
   already launches tool scripts elevated without a second UAC prompt per
   tool. **Subprocess calls must never use `-Verb RunAs` themselves** —
   that would trigger a fresh UAC prompt on every single scan.

## 4. Data contracts (already ~90% defined by the existing JSON logs)

```jsonc
// CatalogItem — now carries which script implements it (§3, §0 #5)
{ "Id": "1.1", "Level": 1, "Module": "Telemetry & Privacy",
  "Name": "...", "Desc": "...", "Target": "...", "DefaultChecked": true,
  "Script": "1.1_Telemetry-Minimum.ps1" }

// ScanResult (unchanged from today's DryRun_*.json)
{ "Id": "1.1", "Name": "...", "Status": "APPLIED|PENDING|REVIEW|SKIPPED|ERROR",
  "Current": "...", "Target": "..." }
```
Pydantic models in `python/backend/models.py` mirror these 1:1.

## 5. FastAPI backend responsibilities

- `GET /api/tools` — static tool list (mirrors `$Tools` in the hub) + cached
  PC specs (`Get-PCSpecs`, called headlessly once at startup).
- `GET /api/{tool}/catalog` — **FPS**: reads `manifest.json` directly, no
  subprocess. **Startup**: one subprocess call to `Enumerate.ps1 -Json`
  (§3). Either way, one fast call/read — never N calls for N items.
- `POST /api/{tool}/scan {checked: [ids]}` — invokes each checked id's own
  `changes\*.ps1` script individually via a bounded thread pool (§5.5),
  collects the per-item results into the same array shape as before;
  backend writes the `.md`/`.json` report (port of the old report section —
  simple string/JSON writing, no reason to keep it PS-side).
- `GET /api/{tool}/report/latest` — serve the last report.
- `POST /api/{tool}/apply {checked: [ids]}` and `POST /api/{tool}/undo` —
  same per-item individual invocation, but **sequential**, not pooled (§5.5,
  §8.5).
- `POST /api/scan-pc` and `GET /api/scan-pc` — the hub-level system
  inventory (§6.7), separate from either tool's catalog — one subprocess
  call, in-memory session cache in `app.state`, not persisted.
- Runs as a single local process — `uvicorn` in a background thread inside
  the same elevated process pywebview opens the window from, bound to
  `127.0.0.1` on a random free port. No network exposure.

## 5.5 Subprocess bridge robustness (`ps_bridge.py` contract)

This is the single highest-risk integration point in the whole rewrite —
every catalog fetch and every scan tunnels through it — so it gets explicit
failure-mode handling, not just a happy-path wrapper.

- **PS host resolution**: resolve once at startup (`shutil.which('pwsh')`,
  fall back to `shutil.which('powershell')`), cache the path. If neither
  exists, fail app startup with a clear fatal state surfaced to the React
  UI as a startup-health banner — the current WPF hub shows a `MessageBox`
  for this same condition; a silently-empty catalog would be worse.
- **Invocation flags**: always `-NoProfile -NonInteractive -ExecutionPolicy
  Bypass -File <script> ...`. `-NonInteractive` is defensive — makes PS
  fail loudly instead of hang if any cmdlet ever tries to prompt.
  `-ExecutionPolicy Bypass` is scoped to this one invocation only, never
  touches the system-wide policy — same "don't change anything beyond
  what's needed" posture as the suite's existing security guardrails.
- **Encoding — a gotcha this codebase has already been bitten by once**:
  the suite needed a UTF-8 BOM fix (see the packaging-bugs history) because
  Windows PowerShell mis-renders its non-ASCII glyphs (`— · → ✓ ◆ ✕`) under
  the console's default codepage. The same failure mode applies to
  subprocess stdout capture — `subprocess.run(..., text=True)` decodes with
  the locale-preferred encoding (often cp1252 on Windows), which will
  mangle those glyphs in `Desc`/`Target`/`Current` strings. Fix on both
  ends: PS headless entry points set `[Console]::OutputEncoding =
  [System.Text.Encoding]::UTF8` before printing JSON; Python passes
  `encoding='utf-8'` explicitly to `subprocess.run(...)`, never relies on
  the default.
- **One-script-per-change invocation model (§3) — cost and how it's
  absorbed:** each checked item is now its own `subprocess.run` call
  instead of one item ID passed into a shared batch call. A cold PS
  process spawn costs roughly 150–300ms before any actual check logic
  runs; 52 *sequential* spawns would be 8–16s of pure overhead before a
  single registry read happens. Two mitigations, applied differently by
  operation because they have different risk profiles:
  - **Scan (`-Check`, read-only): run concurrently**, via a bounded thread
    pool (`concurrent.futures.ThreadPoolExecutor`, ~8 workers). Checks are
    independent and side-effect-free, so there's no ordering risk — this
    is what keeps a 52-item scan's wall-clock time reasonable despite the
    per-item process overhead. The existing "one scan in flight per tool"
    lock (already decided) is unchanged — it still guards the *whole scan
    operation*, which now internally fans out to N pooled calls instead of
    one batch call.
  - **Apply (`-Apply`/`-Undo`, mutating): run sequentially, not pooled.**
    Safety and a simple, easy-to-reason-about incremental undo log (§8.5)
    matter more here than wall-clock time — and the "blocking spinner, up
    to ~2 min" apply UX (§6.6) already budgeted for this being the slower
    of the two operations.
- **Timeouts** (per-call, not per-batch, now that batches don't exist):
  - Catalog listing: 15s ceiling (FPS's manifest read is instant; Startup's
    `Enumerate.ps1` call is the one that needs the ceiling).
  - Each individual `-Check`/`-Apply`/`-Undo` call: ~10–15s ceiling —
    generous margin over the ~150–300ms process overhead plus what's
    typically sub-second check logic (even the `fsutil`/`powercfg`-shelling
    items). `subprocess.run(..., timeout=...)` kills the child on expiry;
    on `TimeoutExpired`, that one item's result becomes a structured
    error — it does **not** need to abort the rest of the pool/sequence
    (see the next point).
  - Overall scan/apply operation: keep a coarser ~120s ceiling as a circuit
    breaker on the whole pooled/sequential run, in case something
    pathological happens (e.g. the thread pool itself hangs) — belt and
    suspenders over the per-item timeout, not a replacement for it.
- **Exit-code contract, now scoped per script instead of per batch**: each
  individual script exits `0` whenever it produced a JSON payload for its
  one item — including a `Status: "ERROR"` result for that item (normal).
  Non-zero exit from one script is a hard `PSBridgeError` **for that Id
  only** — `ps_bridge.py` never salvages partial stdout from that one call,
  but critically, one broken or tampered script can no longer poison an
  entire batch's results the way a bug inside the old shared `Catalog.ps1`
  could have. This is a real robustness improvement the per-script split
  buys for free, not just a cost to absorb.
- **Never paper over an engine failure**: if `returncode == 0` but
  `json.loads(stdout)` still fails (malformed output), that's also a hard
  `PSBridgeError` surfaced with `stdout`/`stderr`/`returncode` attached —
  not silently defaulted to an empty result. This is a PC-optimization tool
  that will eventually gate real system changes once the apply engine
  exists; a silently-empty "nothing to do" result would be actively
  misleading, worse than a visible error.
- **Outer concurrency guard**: one scan (or apply) operation in flight per
  tool at a time — a simple per-tool lock in `ps_bridge.py`, not a global
  lock (the hub can plausibly show cached state for both tools
  independently) and not a queueing system (single-user local desktop app
  — a lock that just rejects/waits is enough). This guards the whole
  operation; the inner per-item thread pool (scan) or sequential loop
  (apply) described above runs *inside* that single held lock.
- **Execution model**: every individual PS invocation is still a plain
  blocking `subprocess.run()` — no `asyncio.create_subprocess_exec`
  anywhere. What's new versus the original one-call-per-batch design is
  that a scan's route handler now dispatches N of those blocking calls
  through a `ThreadPoolExecutor` (§ concurrency note above) instead of
  making one call; apply's route handler makes them in a plain sequential
  loop. Either way FastAPI's sync-route thread-pooling handles the outer
  request without any async subprocess plumbing — that simplification
  still holds, it just now applies at the level of "one route handler
  orchestrating N calls" rather than "one route handler making one call."
- **Frozen-path resolution**: like PS's `$PSScriptRoot` fallback,
  `ps_bridge.py` needs a dual-mode resolver for the target `.ps1` path —
  `Path(__file__).parent` in dev, the PyInstaller-extracted sibling-folder
  location (§8) when frozen.

## 6. pywebview frontend — React

- **One** pywebview window with client-side routing (hub view ↔ tool view),
  replacing today's "hub launches a separate elevated sibling process per
  tool" model. Simpler process model, no `pwsh.exe`-resolution/portability
  code needed at all (that whole block in `PrimePCTuner.ps1` goes away).
- **React 19 + Vite**, built with Claude Code's `frontend-design` skill —
  chosen over vanilla JS specifically so that skill (component-level design
  guidance, not just raw HTML/CSS) is usable for the UI work. Client-side
  routing via a minimal router (react-router or a hand-rolled 2-view
  switch — final call at scaffold time, not a design-doc-level decision).
- **Build step is dev/CI-time only.** `npm run build` emits a static
  `frontend/dist/` (`index.html` + hashed JS/CSS bundles) that pywebview
  loads directly and FastAPI can also serve as static files if needed. The
  shipped exe never runs Node — PyInstaller bundles `dist/`, not the React
  source or `node_modules`. Runtime dependency surface is unchanged from
  the original vanilla-JS plan (§8).
- CSS/theme is still a port of `PrimeUI.ps1`'s XAML styles into React
  components/CSS — the palette and every component (`PrimeCheck`, `BtnSec`,
  `BtnPri`, `RowCard`, `Chip`, the two radial-gradient glows) are already
  fully specified as hex values and layout rules; that translation work is
  unchanged by the React choice, just now done as components instead of
  hand-written DOM/`fetch()` calls.

## 6.5 Tech stack & versions (checked 2026-07-19)

| Layer | Choice | Version | Why |
|---|---|---|---|
| Language | Python | 3.12 or 3.13 | Current safe default for new projects; PyInstaller 6.x supports 3.8–3.15 |
| Web framework | FastAPI | 0.136.x | Pydantic v2 native (5–50x faster validation than v1), current stable |
| ASGI server | uvicorn[standard] | latest | Runs in a background thread inside the same elevated process — not a separate service |
| Validation | pydantic | ≥2.7 | Ships as a FastAPI dependency; models in `python/backend/models.py` (§4) |
| Desktop shell | pywebview | 6.2.x | Windows backend = EdgeChromium (WebView2) — the runtime is preinstalled on Win11 (evergreen), so no extra install for the target PCs per [[pc_setup]] |
| Frontend | React 19.2.x + Vite 8.x | — | Built with Claude Code's `frontend-design` skill for the UI work; `npm run build` emits static `dist/` files that pywebview points at — Node/npm is a **build-time-only** dependency, not a runtime one (§6) |
| Packaging | PyInstaller | 6.21.x | `--onefile`, `--add-data` for the bundled `.ps1` engine folders (§8) |
| PS→Python bridge | `subprocess` (stdlib) | — | No extra package; just `subprocess.run([pwsh_path, '-File', ..., '-Headless', ...], capture_output=True)` and `json.loads()` the stdout |
| Python lint/format | `ruff` | latest | One tool for both (`ruff check` + `ruff format`) instead of flake8+black+isort — fewer moving parts |
| Python types | **skipped for v1** (§8.7a) | — | Pydantic already validates the highest-risk surface (PS↔Python JSON shape) at runtime; mypy would be redundant on that boundary |
| JS/TS lint/format | ESLint (typescript-eslint + react-hooks configs, Vite's default scaffold) + Prettier | latest | Standard for a Vite+React+TS project, not extra ceremony |
| Backend tests | `pytest` + FastAPI `TestClient`, `ps_bridge` mocked | — | Heaviest coverage on `ps_bridge.py` — highest-risk module (§5.5) |
| Frontend tests | Vitest + React Testing Library, smoke-level only | — | A handful of tests (routing, StatusPill variants), not full coverage — matches the app's actual size |
| PS tests | Pester, against a sandboxed `HKCU:\...\_Test\` registry subtree | — | Only way to exercise the apply→undo round-trip (§8.5) without mutating the real CI machine |
| CI | GitHub Actions, `windows-latest` (mandatory — registry/WPF/WebView2/PowerShell are all Windows-only) | — | Full breakdown in §8.7 |

No database, no auth, no external network calls — the whole app talks to
itself on `127.0.0.1` and to `pwsh.exe`/`powershell.exe` as a subprocess.
`requirements.txt` will pin exact versions once `python/` is scaffolded.

## 6.6 React app structure & routing

**Routing — hand-rolled, no react-router.** Only two route "shapes" exist
(Hub, and a single parameterized Tool view for either `fps` or `startup`),
and pywebview's window is chromeless (no address bar, no back/forward
chrome) — there's no browser-history UX to preserve. A dependency-free
state machine in `App.tsx` is simpler and avoids a library that buys
nothing here, the same "don't add abstractions beyond what's needed" logic
that already shaped the bridge design (§5.5):

```ts
type View = { name: 'hub' } | { name: 'tool'; toolKey: 'fps' | 'startup' }
const [view, setView] = useState<View>({ name: 'hub' })
```

Navigation is just `setView(...)` calls: a `ToolCard`'s Launch button →
`{name:'tool', toolKey}`; the topbar/back action in `ToolView` →
`{name:'hub'}`. (If browser-tab dev iteration ever wants URL sync for
convenience, that's a few lines of `history.pushState` — not a reason to
add react-router.)

**Component tree** — maps 1:1 onto the existing XAML resources in
`PrimeUI.ps1` (the `PrimeCheck`/`BtnSec`/`BtnPri`/`RowCard`/`Chip` styles,
the two glow ellipses, the topbar fragment), so the port is mechanical, not
a redesign:

```
src/
  App.tsx                    — owns `view` state, fetches PCSpecs+ToolMeta[] once on mount
  primitives/                — the 5 XAML "Resources" styles, 1:1
    Chip.tsx                  — Border+Text pill (spec chips, stat chips)
    Button.tsx                 — variant='primary'|'secondary' (BtnPri/BtnSec)
    Checkbox.tsx                 — PrimeCheck custom checkbox
    Card.tsx                      — RowCard gradient-bordered container
    StatusPill.tsx                 — APPLIED/PENDING/REVIEW/SKIPPED/ERROR/…SCANNING
  layout/
    BackgroundGlows.tsx        — the two radial-gradient ellipses, rendered once at app root
    Topbar.tsx                  — @Humzeeny branded row, shared by both views
    Footer.tsx                   — @Humzeeny + right-aligned note text (prop: note)
    PageHeading.tsx                — eyebrow/heading/subtitle block, reused by Hub + Tool
    SpecsPanel.tsx                   — WrapPanel of <Chip> from PCSpecs, reused by Hub + Tool
  views/
    HubView.tsx                 — PageHeading + SpecsPanel + ScanPcButton + SystemInventoryPanel + ToolCard × 2 (§6.7)
      ScanPcButton.tsx             — idle/loading/populated states, triggers POST /api/scan-pc
      SystemInventoryPanel.tsx      — collapsed until scanned, then shows installed software/processes summary
      ToolCard.tsx                — Name+Tag+Desc+Meta+Launch Button (onClick → setView)
    ToolView.tsx                — PageHeading + SpecsPanel + StatsPanel + ChecklistPanel + ToolbarBar
      StatsPanel.tsx               — WrapPanel of scan-count Chips (applied/pending/review/skipped/errors)
      ChecklistPanel.tsx            — groups CatalogItem[] by Level+Module (mirrors WPF's Group-Object)
        LevelGroup.tsx                — level/module header + its ChecklistRows
          ChecklistRow.tsx             — Checkbox + id-pill + Name/Desc/Target + StatusPill
      ToolbarBar.tsx                 — Select all/none/Uncheck L3/Open report + status text + Re-scan
  api.ts                      — typed fetch wrappers + the shared TS types below
  theme.css                   — ported palette + primitive styles from PrimeUI.ps1
```

**Shared types in `api.ts`** — hand-mirrored from the Pydantic models (§4),
not code-generated. Only 4 small shapes exist; an OpenAPI-codegen pipeline
would be more tooling than the surface area justifies — the discipline is
just "keep these in sync by hand," low-risk at this size:

```ts
export type PCSpecs = { CPU: string; Cores: string; GPU: string; RAM: string;
  OS: string; Disks: string; NIC: string; Elevated: boolean }
export type ToolMeta = { Key: 'fps' | 'startup'; Name: string; Tag: string;
  Desc: string; Meta: string }
export type CatalogItem = { Id: string; Level: number; Module: string;
  Name: string; Desc: string; Target: string; DefaultChecked: boolean }
export type ScanResult = { Id: string; Name: string;
  Status: 'APPLIED' | 'PENDING' | 'REVIEW' | 'SKIPPED' | 'ERROR';
  Current: string; Target: string }
export type SystemInventory = { ScannedAt: string;
  InstalledSoftware: { Name: string; Version: string }[];
  RunningProcesses: { Name: string; Pid: number }[] }
```

**State management: none beyond `useState`/`useEffect`.** `PCSpecs`/
`ToolMeta[]` are fetched once in `App.tsx` and passed down as props (only 2
levels deep — not worth a Context); each view owns its own loading/error
state locally. No Redux/Zustand, no TanStack Query — a single-user local
app hitting `127.0.0.1` has no caching/pagination/dedup problem those
libraries solve.

**Decided — scan progress UX (confirmed 2026-07-19): ship the v1 regression.**
Today's WPF app scans live — each row flips SCANNING → APPLIED/PENDING/…
as `Invoke-PrimeScan` works through the list, with a running "Checking 12
of 52: 1.13…" status line. §5.5's bridge returns **one JSON array after the
whole scan finishes**, so v1's `ToolbarBar` shows a single "Scanning… (up
to ~2 min)" spinner state and all `ChecklistRow`s paint at once when
`POST /scan` resolves — no per-row live status. Zero changes to the
already-locked bridge contract; fastest to build. Two upgrade paths stay on
the table if this feels too coarse once it's actually running: NDJSON
stdout streaming proxied as SSE (true per-row parity, changes §5.5's output
contract), or a polling `GET /scan/progress` background-task endpoint for
an "N of M" progress bar (middle ground, smaller bridge change). Neither is
in scope now.

## 6.7 "Scan PC" — system inventory (user-directed, confirmed 2026-07-19)

A new hub-level feature, decided via 3 clarifying questions since "gets all
information" and "script fills" were genuinely ambiguous against the
architecture already locked in §3/§5.5/§8.5:

1. **Scope**: broad PC inventory, not a full run of every check. On top of
   the specs chips already fetched at startup (§5's `GET /api/tools`), the
   "Scan PC" button gathers **installed software** (name+version, read from
   the registry `Uninstall` keys — `HKLM`/`HKLM\...\Wow6432Node`/`HKCU`,
   **not** `Get-CimInstance Win32_Product`, which is known to trigger MSI
   self-repairs and is slow enough to be a real anti-pattern here) and
   **running processes** (`Get-Process`). Extensible later, not meant to be
   exhaustive on day one.
2. **Downstream use**: both — populates a new hub UI panel immediately, and
   is available to be passed into individual script invocations as
   optional pre-fetched context (see the constraint below).
3. **Persistence**: session-scoped, not cross-session — refined below into
   a concrete mechanism once it became clear individual scripts need to
   *read* this data, not just the Python API layer.

### PS side — the "PC Scan file" (refined 2026-07-19)
One new script, `shared\Invoke-SystemScan.ps1 -Json` — a single subprocess
call (not per-item; this is one coherent broad read, not
individually-invoked "changes" the way §3's catalog items are). Reuses
`Get-PCSpecs` for the hardware fields already established, adds the
installed-software and running-process enumeration. **Writes its result to
a well-known file, `shared\cache\SystemScan.json`, in addition to printing
it to stdout** — this file *is* "the PC Scan file" individual change
scripts read from for supplementary context (§3's Windows Changes/Services/
etc. scripts, via a new `Get-CachedSystemScan` helper in
`shared\PrimeChecks.ps1` that reads the file and returns `$null` if it's
missing). A file is simpler for standalone-invoked scripts to consult than
threading a JSON blob through CLI parameters on every subprocess call —
and it's what makes the "optional pre-fetched context" mechanism below
concrete rather than hand-wavy. The file is overwritten fresh on every
"Scan PC" click and isn't trusted across app restarts (the Python app
clears/ignores it on startup) — session-scoped in spirit, file-backed in
mechanism.

### Python side
- `POST /api/scan-pc` — invokes `Invoke-SystemScan.ps1 -Json`, which
  writes `shared\cache\SystemScan.json` and returns the same JSON via
  stdout; the backend caches that response in `app.state.system_scan`
  (plain in-memory attribute — no cache library) purely so `GET
  /api/scan-pc` can serve it back to the UI without re-reading the file.
- `GET /api/scan-pc` — returns the current cached scan, or `null`/404 if
  the button hasn't been clicked yet this session. Lets `HubView` restore
  its populated state if the user navigates to a tool and back, without
  re-scanning.

### React side
`ScanPcButton` (idle → loading → populated) and `SystemInventoryPanel`
(collapsed/empty until scanned, then a summary — e.g. "142 installed
programs · 87 running processes" — expandable to the full lists), both new
on `HubView` per the tree above. Not auto-triggered on app launch —
user-initiated by design, matching the "button" framing of the request.

### The one hard constraint on "feeds the scripts": never for the
### game-detection safety check
§8.5's `Test-GameRunningTracked` pre-flight (refuses an entire apply run if
a game process is detected) **must always query live at apply time**, never
accept the cached process list from a "Scan PC" run that could be minutes
or hours stale — a user could launch a game between scanning and clicking
Apply, and a stale "no game running" read there would be actively unsafe,
not just imprecise. This is the one place "feeds the scripts" is
deliberately **not** wired up, and it's called out explicitly so it isn't
quietly done wrong during implementation.

Where pre-fetched data *is* a reasonable win: Startup Optimizer's
`Get-StartupAnnotation` pattern-matching (today just string-matches Run-key
value names like "Discord"/"Steam") could cross-reference the installed-
software list for a more grounded annotation instead of a bare name guess
— a genuine, safe use of the cached data, not a safety-relevant one.

**Scripts must still work standalone without pre-fetched data.** Any
script that wants supplementary context calls `Get-CachedSystemScan` (§3),
which returns `$null` if `shared\cache\SystemScan.json` doesn't exist —
the script then falls back to querying that one piece of information
itself. Pre-fetched data is always an optional read, never a hard
dependency. This preserves §3's whole point: each script stays
independently invokable and testable (§8.7's Pester suite runs scripts
directly, with no "Scan PC" step involved, so the file simply won't exist
in that context and every script must tolerate that) — making a script
*require* the file would undermine the isolation the per-script split was
built for.

### Scope boundary: Python/React only, not retrofitted into the legacy WPF app
Per §0 #3 the WPF app is kept indefinitely but is the not-actively-
developed track (§8.8's `CHANGELOG.md` framing) — "Scan PC" is a new v2.0.0
feature, not backported to `PrimePCTuner.ps1`. Noting this as a deliberate
scope call, not an oversight.

## 7. Proposed folder structure

```
C:\Apps\PcTuner-Open-Source\
  changes\                                (NEW — sector-organized, replaces both tools' lib\Catalog.ps1, §3)
    Windows Changes\                        — ~21 unique files (deduped across old FPS/Startup catalogs)
      1.1_Telemetry-Minimum.ps1               — one item's Check/Apply/Undo, ~15-30 lines
      1.2_StartMenuAds-Off.ps1
      ... (Telemetry & Privacy, Bloat Tasks, Edge Containment, Apps, Security Trade-offs,
           + Startup's non-duplicate Windows Extras/Leftover Toggles)
    Services\                               — 19 files (2S.1-2S.19)
      DiagTrack.ps1
      ...
    Performance & Hardware\                 — 13 files (Filesystem, Network Adapter, Power & Input)
      ...
    PC Startup\                             — dynamic, action-type scripts, not per-instance
      Enumerate.ps1                            — discovery step, PC-specific, one subprocess call
      RunKeyEntry.ps1                           — Check/Apply/Undo, parameterized per discovered entry
      StartupFolderShortcut.ps1
      ScheduledTask.ps1
  FPSOptimization\manifest.json           (NEW — Id/Level/Module/.../Script(sector-relative path) for its items)
  StartupOptimization\manifest.json       (NEW — same, for its static items; dynamic ones come from Enumerate.ps1)
  shared\PrimeUI.ps1                     (WPF app kept working, but its scan loop now shells out
                                           to changes\<Sector>\*.ps1 per item instead of running in-process, §3)
  shared\PrimeChecks.ps1                 (NEW — shared I/O primitives: Test-RegValue, Set-RegValueTracked,
                                           Test-ServiceStartMode, Get-CachedSystemScan, etc., dot-sourced by every change script)
  shared\PrimeHeadless.ps1               (NEW — mode-dispatch/JSON-output plumbing, no WPF/elevation, §3)
  shared\Invoke-SystemScan.ps1           (NEW — the "Scan PC" broad inventory, writes shared\cache\SystemScan.json, §6.7)
  shared\cache\SystemScan.json           (generated at runtime by Invoke-SystemScan.ps1 — "the PC Scan file," §6.7, not committed)
  FPSOptimization\Start-FPSOptimization.ps1        (+ -Headless flag, thin dispatcher into changes\<Sector>\*.ps1, §3)
  StartupOptimization\Start-StartupOptimization.ps1 (+ -Headless flag, thin dispatcher into changes\<Sector>\*.ps1, §3)
  python\
    app.py                  — entry: elevation check, start uvicorn thread, open pywebview window
    backend\
      main.py                — FastAPI app + routes
      ps_bridge.py            — subprocess wrapper: run pwsh headless, parse JSON, timeout/error handling
      reports.py               — write .md/.json reports (ported from Invoke-PrimeScan)
      models.py                 — pydantic: CatalogItem, ScanResult, ToolMeta, SystemInventory (§6.7)
    frontend\                 — React + Vite source (dev-time only, not shipped)
      src\                      — full component tree in §6.6
        App.tsx                   — owns `view` state (hand-rolled router, §6.6)
        primitives\                — Chip, Button, Checkbox, Card, StatusPill
        layout\                      — BackgroundGlows, Topbar, Footer, PageHeading, SpecsPanel
        views\                          — HubView(+ScanPcButton+SystemInventoryPanel+ToolCard, §6.7),
                                           ToolView(+StatsPanel/ChecklistPanel/ToolbarBar)
        api.ts                            — typed fetch wrappers + shared TS types (§6.6, mirrors §4)
        theme.css                          — ported palette from PrimeUI.ps1 (§6)
      package.json
      vite.config.ts
      dist\                    — `npm run build` output; PyInstaller bundles THIS, not src\
    requirements.txt
    build.spec                — PyInstaller spec, bundles frontend\dist\ + the .ps1 engine folders as data
  docs\
    PYTHON_REWRITE_DESIGN.md   (this file)
```

Old PS entry points stay in place and keep working standalone — nothing
is deleted by this rewrite; Python only adds a new front door.

## 8. Packaging

- Build is two stages: (1) `npm run build` in `frontend/` produces
  `frontend/dist/` — a plain static site, no server, no Node needed to run
  it; (2) PyInstaller onefile build of `python/app.py` bundles
  `frontend/dist/`, `FPSOptimization/`, `StartupOptimization/`, `shared/`
  via `--add-data`, extracted next to the exe at first run (same "ship the
  sibling folders" lesson already learned from the ps2exe zip release —
  subprocess needs real `.ps1` files on disk, not PyInstaller's virtual FS).
- End-user runtime dependencies are unchanged from the original vanilla-JS
  plan: `powershell.exe`/`pwsh.exe` (every Windows install has one) +
  WebView2 (preinstalled on Win11). **Node/npm is never required on the
  target PC** — only on the dev machine building the release.

## 8.5 Apply engine design

This is the piece that actually changes the system, so it gets the same
"never paper over a failure" rigor as §5.5, plus real revert capability —
dry-run got the suite this far precisely by promising nothing changes;
apply has to keep that trust by promising every change is undoable.

### Apply/Undo modes on the per-change scripts (§3)

Each item's standalone script (`changes\<Id>_<Slug>.ps1` for FPS, the
per-action-type scripts for Startup) needs `-Apply -Json` and `-Undo -Json`
modes alongside `-Check -Json` — and critically, `-Check`'s `Current`
field is a **display string** ("AllowTelemetry = 1"), not a typed value,
so it can't be replayed to undo a change. Fix: `-Apply` calls a
self-contained shared primitive from `shared\PrimeChecks.ps1` that reads
the old value itself, writes the new one, and returns both — the script
doesn't need its own bespoke read-old/write-new logic, just a one-line
call to the right tracked primitive for its one setting:

```powershell
# New sibling helpers alongside the existing Test-RegValue etc.
function Set-RegValueTracked {
    param($Path, $Name, $Value)
    $existed = $false; $prev = $null
    try { $prev = (Get-ItemProperty $Path $Name -EA Stop).$Name; $existed = $true } catch {}
    New-Item -Path $Path -Force -EA SilentlyContinue | Out-Null
    Set-ItemProperty -Path $Path -Name $Name -Value $Value
    [pscustomobject]@{ Success = $true; PreviouslyExisted = $existed; PreviousValue = $prev }
}
```
Same pattern for `Set-ServiceStartModeTracked`, `Disable-ScheduledTaskTracked`,
and — for the Startup Optimizer's file-based items — a
`Remove-StartupEntryTracked` that **copies the shortcut file to a backup
path before deleting it** (a shortcut's binary content can't be
reconstructed from a JSON string the way a registry DWORD can; skipping
this would make those items silently non-revertible, breaking the
"everything is undoable" promise).

### Undo record + log

Every successful Apply call appends one record to a run's undo log:
```jsonc
{ "Id": "1.1", "Kind": "RegistryValue", "Path": "HKLM:\\...", "Name": "AllowTelemetry",
  "PreviouslyExisted": true, "PreviousValue": 3, "BackupFile": null }
```
(`BackupFile` populated only for file-based items, per above.)
**Written incrementally, one record per successful item — not batched at
the end** — so a hard crash or forced kill mid-run still leaves a valid
undo trail for everything that already succeeded; batching to the end
would silently lose that safety net on exactly the failure path it exists
for.

### Restore point (coarse safety net, on top of the undo log)

Before the first item of an apply run, `Checkpoint-Computer -Description
"PcTuner-Open-Source pre-apply <timestamp>"`. **Known gotcha**: Windows throttles
System Restore to one checkpoint per `SystemRestorePointCreationFrequency`
(default 1440 min = 24h) — a second apply run same day won't get a fresh
restore point. Not working around this by touching that registry value
(scope creep, and it's a system-wide setting, not portable-tool territory)
— the granular undo log is the primary safety net; the restore point is a
once-a-day coarse backstop on top of it, not the only line of defense.

### Selection, sequencing, and hard guardrails

- Apply only ever touches ids that are (a) checked in the UI **and** (b)
  scanned `PENDING` on the most recent scan — re-validated server-side,
  never trusted from client state alone, since this mutates the system.
  `REVIEW` items (`Compliant = $null`) are **never** eligible for apply —
  that status exists specifically because the item needs human judgment.
- **Sequential, one item at a time** — per §5.5's concurrency split, apply
  invokes each item's script individually and sequentially (not pooled
  like scan): one item's failure doesn't block the other independent
  items, it's just recorded as `ERROR` and skipped for undo purposes
  (nothing to undo if nothing was written) — the same try/catch-and-
  continue posture as before, just expressed as a Python-side loop over
  individual subprocess calls now instead of an in-process PS loop.
- The suite's existing hard guardrails (Defender real-time never touched,
  anticheat services Manual-never-Disabled, no Temp/root Defender
  exclusions, WAN Miniport never touched) are enforced by **authorship
  review, not runtime logic** — the catalog is a small, human-curated set
  of files (52 for FPS, 4 action-type scripts for Startup), so any new or
  edited script's `-Apply` logic gets manually checked against these
  guardrails before being added — and the per-script split actually makes
  that review easier, since each file's blast radius is legible at a
  glance instead of buried in one shared catalog.
- **Game-aware pre-flight, not per-item**: before an apply run starts, a
  `Test-GameRunningTracked` check (known game process names via
  `Get-Process`) — if a game is detected, the **entire apply run is
  refused** with a clear message, not silently skip-just-that-item. FPS
  Optimizer's whole premise is "run this between sessions," so a hard
  pre-flight stop is simpler and safer than per-item judgment calls.

### API + UI (reuses §6.6's already-decided patterns, doesn't reinvent them)

- `POST /api/{tool}/apply {checked: [ids]}` — mirrors `/scan`'s shape.
  Requires an explicit **second confirmation** in the UI before firing
  (modal: "About to apply N changes — a System Restore Point will be
  created first. [Cancel] [Apply N changes]"), the same
  confirm-before-hard-to-reverse-action posture used everywhere else in
  this workflow. If any selected item is Level 3/Aggressive, the modal
  calls that out by count specifically, echoing the existing "AGGRESSIVE"
  labeling already in the catalog/UI.
- Progress UX reuses the **already-decided** §6.6 pattern exactly — single
  blocking spinner, all rows resolve when the request completes. Not
  re-litigating that decision for a second endpoint.
- `POST /api/{tool}/undo` — v1 scope is **undo the most recent apply run
  as a whole**, no partial/single-item undo and no history browser; reads
  the latest `UndoLog_*.json`, reverses each record (write back
  `PreviousValue` or delete the key if `PreviouslyExisted` is false,
  restore the backed-up file, etc.), reports per-item `REVERTED|ERROR`.
- Reports: `ApplyLog_<timestamp>.json`/`.md` in the same `logs/` folder as
  today's dry-run reports (§0 decision #4), same shape as `ScanResult` plus
  `PreviousValue`/`NewValue`. `UndoLog_<timestamp>.json` is a separate,
  machine-oriented file — superset of info needed to programmatically
  revert, not meant for human reading.

### Explicitly out of scope for v1 apply engine

- No scheduled/automatic apply — always user-initiated from the UI.
- No partial undo of a single item from history, no cross-run history
  browser — v1 undo is "revert the most recent run," full stop.
- No override of the Windows restore-point throttle.

## 8.7 Dev/CI tooling

### Python
- **`ruff`** for both lint and format (`ruff check .` / `ruff format .`)
  — one tool instead of flake8+black+isort. Matches the "keep the stack
  thin" posture that's shaped every other tooling call in this doc.
- **mypy — open question, not decided here (see §8.7a below).**

### React/TS
- **ESLint** (typescript-eslint + react-hooks configs — Vite's own
  `--template react-ts` scaffold ships these by default, nothing extra to
  configure) + **Prettier** for formatting. This is the standard, expected
  baseline for a Vite+React+TS project, not additional ceremony the way a
  state library or codegen pipeline would be.
- **`tsc --noEmit`** as the type-check gate — effectively free since
  TypeScript was already chosen for `api.ts` (§6.6); no separate tool to
  add.

### Testing
- **Backend**: `pytest` + FastAPI's `TestClient` (httpx-based). Heaviest
  coverage goes to `ps_bridge.py` (§5.5) with `subprocess.run` mocked —
  it's the highest-risk module in the app, exercising the timeout,
  non-zero-exit, and malformed-JSON error paths specifically.
- **Frontend**: Vitest + React Testing Library, **smoke-level only** — a
  handful of tests (routing switches view on `setView`, `StatusPill`
  renders the right variant per status) rather than full component
  coverage. The app is two views and no state library; exhaustive frontend
  testing would be more ceremony than the surface area justifies.
- **PowerShell — the one genuinely new piece**: introduce **Pester** to
  unit-test the new `Set-*Tracked`/undo helpers from §8.5 against a
  **sandboxed registry subtree** (e.g. `HKCU:\Software\PcTuner-Open-Source\_Test\`,
  created fresh and torn down per test run) instead of real system paths.
  This is the only way to actually exercise the apply→undo round-trip
  (write → capture previous value → undo → assert restored) in CI without
  mutating the CI machine's real settings — and it directly backs the
  "everything is undoable" promise §8.5 makes, rather than just asserting
  it in a design doc. The existing `-SelfTest` convention (headless window
  build + exit) stays for the read-only entry points; Pester is additive,
  specifically for the apply/undo logic that `-SelfTest` was never meant
  to cover.

### CI pipeline
GitHub Actions, `windows-latest` runner — mandatory, not a choice, since
registry access, WebView2, and PowerShell are all Windows-only (no cheaper
`ubuntu-latest` option here). Free for a public repo. Runs on PRs (and
pushes to feature branches, matching the multi-branch git workflow already
in use):
1. **Python**: `ruff check`, `ruff format --check`, `pytest`.
2. **Frontend**: `npm ci` (not `npm install` — reproducible, lockfile-
   pinned), `eslint`, `tsc --noEmit`, `vitest run`, `npm run build` (this
   last step also catches build-breaking errors before merge, for free).
3. **PowerShell**: Pester suite (sandboxed registry) + `-SelfTest`
   invocations of every headless entry point — `-ListCatalog`/`-Scan` can
   run for real in CI since they're read-only; `-Apply`/`-Undo` are only
   exercised via Pester against the sandbox, never via the real entry
   point in CI.
- **Not in v1 CI, deliberately deferred**: a full PyInstaller onefile build
  in CI. Feasible on `windows-latest` but slow, and there's no code to
  build yet — add it once the `python/` scaffold exists and this becomes a
  real question rather than a hypothetical one.

### Local dev loop — no `pre-commit` framework
Your existing git workflow already has Claude run sanity checks *before*
showing a diff and asking to commit — adding a `pre-commit` hooks
framework on top would be a second, overlapping enforcement layer for the
same thing. Instead, the "sanity checks myself" step just becomes these
commands, run manually (by Claude, per that existing rule) before every
commit: `ruff check && ruff format --check && pytest` (Python side),
`npm run lint && npm run typecheck && npm test` (frontend side). No new
automation, just filling in what the existing rule already asks for.

### `.gitattributes`
The repo currently mixes conventions out of necessity — `.ps1` files need
CRLF + a UTF-8 BOM (the packaging-bugs history in this doc explains why).
Python/JS ecosystems conventionally use LF. Rather than let this become
incidental diff noise, add a `.gitattributes` once `python/`/`frontend/`
exist: `*.ps1 text eol=crlf`, `*.py text eol=lf`, `*.ts *.tsx *.css text
eol=lf`.

### 8.7a mypy — decided: skip for v1 (confirmed 2026-07-19)

Pydantic already validates the highest-risk boundary (`ps_bridge.py`'s
parsed JSON vs. the models) at runtime on every request — mypy would catch
the same class of bug a second, redundant way, for the cost of a new
dependency, a new CI step, and annotation overhead, on a stack that's been
kept deliberately thin at every other turn (no react-router, no state
library, no codegen, no async subprocess). Revisit only if `ps_bridge.py`/
`models.py` grow enough that static checking starts pulling its own
weight.

## 8.8 Versioning & release process

### Version scheme — decided: continue the lineage, v2.0.0 (confirmed 2026-07-19)
The PS suite already shipped v1.0.0. The Python rewrite is versioned as
**v2.0.0**, not a reset to v1.0.0 — same product, one coherent release
history on the GitHub Releases page, even though the old PS app (§0
decision #3) keeps working standalone indefinitely. Framing: v2.0.0 is
PcTuner-Open-Source's next major version; the PS app becomes the maintained-but-
not-actively-developed legacy track under that same release history, not a
separately-versioned sibling product.

### One app version, not three per-tool versions
Today's UI shows independent per-tool versions (FPS Optimizer "v0.3",
Startup Optimizer "v0.1") because they're three separate WPF
windows/processes. §6.6 collapses that into one pywebview window/one React
SPA — so there's **one app version** for the whole shipped exe, not three.
Catalog *content* changes (new checks, level changes) keep tracking through
the existing per-tool `CHANGES.md` files (`FPSOptimization/CHANGES.md`
already exists) — that convention doesn't need to change, it's just no
longer tied to an exe-version number of its own.

### Single source of truth for the version string
One value, defined once (`python/backend/__version__.py` or a plain
`python/VERSION` file), consumed three ways — never hand-duplicated:
- `build.spec` reads it for the PyInstaller exe's Windows file-version
  resource (Properties → Details tab — today's ps2exe build likely has
  this blank; low-effort thing to get right this time).
- `GET /api/version` exposes it over the API.
- The React footer **fetches it at runtime** from that endpoint — same
  "fetch, don't bake in" pattern already used for `PCSpecs`/`ToolMeta`
  (§6.6) — rather than injecting it into the JS bundle at build time. This
  is what actually prevents version-string drift between what the exe
  really is and what the UI claims to be, a real bug class otherwise.
- `frontend/package.json`'s own `version` field is cosmetic/irrelevant —
  the frontend isn't published as an npm package, so it's not a second
  source of truth to keep in sync with anything.

### Pre-release checkpoints during the build
This is a multi-session rewrite. Use GitHub pre-release tags
(`v2.0.0-alpha.1`, `-alpha.2`, …, `-beta.1`) for your own in-progress
testing builds as the scaffold comes together, each marked "pre-release"
(not "latest") on GitHub. The **first `v2.0.0` tag** (non-prerelease,
marked latest) only happens once it clears the same verification bar the
v1.0.0 PS release already set: clean zip extraction → `--self-test` →
real launch → hub renders specs + both tool cards → each tool's scan
completes and renders results → apply flow reaches its confirmation modal.
Apply's actual system-mutating path is verified via the §8.7 Pester
sandbox suite, not by manually applying changes to a real machine during
release verification.

### Release assets — same two-asset pattern as today, for the same reason
PyInstaller can embed `frontend/dist/` inside the onefile exe itself
(extracted to `_MEIPASS` at runtime), but the `.ps1` catalog engine still
needs to exist as **real files on disk** next to the exe for `subprocess`
to invoke (§8). So the release keeps shipping: a bare `PcTuner-Open-Source.exe`
(same caveat as today — won't actually run standalone without the sibling
folders) + `PcTuner-Open-Source-v2.0.0-win.zip` containing the exe plus
`FPSOptimization/`, `StartupOptimization/`, `shared/`.

### CHANGELOG.md — new, doesn't exist today
Add one repo-root `CHANGELOG.md` narrating the app-level release train
(`v1.0.0` PS, `v2.0.0` Python, …) with two clearly labeled sections —
"PcTuner-Open-Source (PowerShell/WPF) — legacy, maintained not actively
developed" and "PcTuner-Open-Source (Python) — active development" — since the
repo now genuinely ships two parallel artifacts and there's currently
nowhere that states which one is "current." Per-tool `CHANGES.md` files
keep doing what they already do (catalog-content history); this is a new,
higher-level index above them.

### No new release automation
No semantic-release / conventional-commits / auto-version-bump tooling —
version bumps and tags stay a manual, deliberate act (a human — or Claude,
on explicit request — edits the one version file and creates the git tag),
the same way both PS renames and the v1.0.0 release were already done with
explicit end-to-end verification each time. Consistent with §8.7's "no
pre-commit framework" call: this codebase adds automation for things that
are safe to automate, not for gates that should stay a deliberate human
checkpoint.

### Dependency on the still-open `main` question
None of this can produce a real `v2.0.0` tag until `main` exists — it's
currently **unborn**, and per the standing git rule that's a hard stop
requiring explicit approval, already flagged as pending in §10 and in
memory. Not resolving that here; just noting the release process is
blocked on it, not forgotten.

## 9. Explicitly out of scope for this first cut

- Anything beyond hub view + one tool's checklist view + the apply/undo
  flow specified in §8.5.

## 10. Next step

Design is approved (§0) and now **fully specified end-to-end** — elevation
(§3.5), bridge robustness (§5.5), React structure/routing (§6.6), apply
engine (§8.5), dev/CI tooling (§8.7), and versioning/release (§8.8) are all
locked. Next session's work: implement §3 (`PrimeHeadless.ps1`
+ `-Headless` flags on the two tool entry points) first, verify headless
`-ListCatalog`/`-Scan` output matches the existing JSON shape byte-for-byte
against a real scan, *then* start the `python/` scaffold in §7.
