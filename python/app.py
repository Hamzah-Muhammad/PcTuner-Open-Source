"""Desktop entry point: elevation check, FastAPI in a background thread,
pywebview window pointed at the built frontend (§3.5, §6).

Usage:  python app.py              (self-elevates via UAC)
        python app.py --self-test  (skip elevation + webview, verify wiring)
"""

from __future__ import annotations

import argparse
import ctypes
import os
import socket
import sys
import threading
from pathlib import Path

# PyInstaller's --windowed (console=False) build has no console at all, so
# sys.stdout/sys.stderr are None rather than a hidden stream — the real root
# cause of the "UAC yes, then nothing" bug (found 2026-07-22 by comparing
# against a console=True debug build, which worked): uvicorn's logging setup
# and app.py's own print(..., file=sys.stderr) calls hit a None stream, and
# depending on exactly where that happens the server thread can die silently
# before ever binding the port — no traceback, no dialog, no event log entry,
# because there's no stream anywhere to write one to. Must run before uvicorn
# (or anything else that configures logging) is imported.
if sys.stdout is None:
    sys.stdout = open(os.devnull, "w")
if sys.stderr is None:
    sys.stderr = open(os.devnull, "w")

import uvicorn

from backend import paths
from backend.main import app as fastapi_app

# Sibling-of-exe when frozen (matches backend.paths' REPO_ROOT — the .ps1
# engine folders live here), this file's own folder in dev mode.
REPO_ROOT = paths.REPO_ROOT

if getattr(sys, "frozen", False):
    # frontend/dist is embedded in the onefile bundle (§8's "PyInstaller can
    # embed frontend/dist/ inside the exe itself, extracted to _MEIPASS at
    # runtime" — unlike the .ps1 folders, nothing external reads these files
    # by path, so bundling is safe here).
    FRONTEND_DIST = Path(sys._MEIPASS) / "frontend_dist"
else:
    FRONTEND_DIST = REPO_ROOT / "frontend" / "dist"


def is_admin() -> bool:
    try:
        return bool(ctypes.windll.shell32.IsUserAnAdmin())
    except Exception:
        return False


# ShellExecuteW returns HINSTANCE — pointer-sized (64-bit on 64-bit Windows).
# ctypes' default restype for an unconfigured function is a 32-bit c_long,
# which would silently truncate that return value if it were ever large.
# In practice ShellExecuteW's real return values are always small
# documented codes (checked directly — "open" and "runas" both returned 42
# under the old, unconfigured restype too), so this wasn't the cause of the
# "click UAC yes, nothing opens" bug investigated the same day — that
# remains unresolved. Kept anyway as the objectively more correct way to
# call a pointer-returning WinAPI function through ctypes.
_shell_execute_w = ctypes.windll.shell32.ShellExecuteW
_shell_execute_w.restype = ctypes.c_void_p
_shell_execute_w.argtypes = [
    ctypes.c_void_p,
    ctypes.c_wchar_p,
    ctypes.c_wchar_p,
    ctypes.c_wchar_p,
    ctypes.c_wchar_p,
    ctypes.c_int,
]


def relaunch_elevated() -> bool:
    """Mirrors PS's Invoke-PrimeBootstrap elevation step (§3.5). Returns True
    if a relaunch was fired (caller should exit immediately after).

    Frozen (PyInstaller onefile): the exe itself is the target, no script
    path needed. Dev mode: python.exe is the target and the script path has
    to be threaded through as the first parameter. `sys.argv[1:]` (not
    `sys.argv`) — argv[0] is the running script/exe's own path, already
    covered by `target`/`__file__`; re-including it as a parameter would
    hand app.py a stray positional it doesn't define and argparse would
    reject the relaunch outright.
    """
    extra_args = [f'"{a}"' for a in sys.argv[1:]]
    if getattr(sys, "frozen", False):
        target = sys.executable
        params = " ".join(extra_args)
    else:
        target = sys.executable
        params = " ".join([f'"{__file__}"', *extra_args])
    try:
        result = _shell_execute_w(None, "runas", target, params, str(REPO_ROOT), 1)
        # ShellExecuteW returns a value > 32 on success (result is None or a
        # real pointer value now that restype is correctly configured above).
        return bool(result) and result > 32
    except Exception:
        return False


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def mount_frontend() -> str | None:
    """Serves frontend/dist from the same FastAPI instance/origin the API
    lives on — zero CORS config, matches §8's packaging plan. Returns a
    warning message if the build is missing (never crashes: an API-only
    window is still more useful than no window)."""
    if not (FRONTEND_DIST / "index.html").is_file():
        return f"Frontend build not found at {FRONTEND_DIST} — run `npm run build` in frontend/ first."
    from fastapi.staticfiles import StaticFiles

    fastapi_app.mount("/", StaticFiles(directory=str(FRONTEND_DIST), html=True), name="frontend")
    return None


def run_server(port: int) -> None:
    uvicorn.run(fastapi_app, host="127.0.0.1", port=port, log_level="warning")


def wait_for_server(port: int, timeout_s: float = 35.0) -> bool:
    """Polls /api/health until the ASGI server is actually accepting
    connections. Necessary, not cosmetic: FastAPI's lifespan startup (a real
    PowerShell system scan — specs + installed software + processes, easily
    a few seconds) runs BEFORE uvicorn starts serving, so opening the webview
    window immediately after starting the server thread is a real race —
    the window loads before anything is listening and WebView2 shows its own
    "can't reach this page" with no automatic retry."""
    import time
    import urllib.request

    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        try:
            urllib.request.urlopen(f"http://127.0.0.1:{port}/api/health", timeout=1)
            return True
        except OSError:
            time.sleep(0.1)
    return False


WINDOW_TITLE = "PcTuner-Open-Source by @Humzeeny"


def _bring_to_front(_window) -> None:
    """Runs in a background thread once pywebview's GUI loop is up (webview.
    start(func, args)'s documented pattern). Real, confirmed bug (not
    speculative): a process that just self-elevated via UAC opens its window
    successfully — server up, WebView2 fully initialized, IsWindowVisible=True
    — but Windows' foreground-lock protection stops it from stealing focus
    from whatever was in the foreground before elevation. The window sits
    behind everything else with no taskbar flash, indistinguishable from
    "didn't open" unless the user happens to Alt+Tab (confirmed via direct
    win32 window enumeration during the 2026-07-21 investigation, and
    verified fixed end-to-end by the user on a real UAC-elevated launch).

    Locates the window via FindWindowW(title) rather than `window.native.
    Handle` — a `.native.Handle`-based version was tried after an automated
    review flagged the title lookup as a spoofing surface (see git history),
    but that version produced NO window at all under a real interactive UAC
    elevation (only verified by the author under an already-elevated test
    session, which turned out not to reproduce the real failure mode — same
    lesson as the rest of this investigation). Reverted to the version
    actually proven to work end-to-end, closing the spoofing gap a different
    way: verify the found window's owning process is this one before
    touching it, instead of switching to an unverified retrieval mechanism.
    """
    import time

    user32 = ctypes.windll.user32
    own_pid = ctypes.windll.kernel32.GetCurrentProcessId()

    hwnd = 0
    for _ in range(50):
        candidate = user32.FindWindowW(None, WINDOW_TITLE)
        if candidate:
            owner_pid = ctypes.c_ulong()
            user32.GetWindowThreadProcessId(candidate, ctypes.byref(owner_pid))
            if owner_pid.value == own_pid:
                hwnd = candidate
                break
        time.sleep(0.1)
    if not hwnd:
        return
    SW_RESTORE = 9
    HWND_TOPMOST = -1
    HWND_NOTOPMOST = -2
    SWP_NOMOVE = 0x0002
    SWP_NOSIZE = 0x0001
    SWP_SHOWWINDOW = 0x0040

    user32.ShowWindow(hwnd, SW_RESTORE)
    user32.SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW)
    user32.SetWindowPos(hwnd, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW)
    user32.SetForegroundWindow(hwnd)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true", help="skip elevation + webview, verify wiring")
    args = parser.parse_args()

    if not args.self_test and not is_admin():
        if relaunch_elevated():
            sys.exit(0)
        print("Elevation declined — continuing unelevated; some checks may show REVIEW.", file=sys.stderr)

    warning = mount_frontend()
    if warning:
        print(f"WARNING: {warning}", file=sys.stderr)

    port = free_port()
    server_thread = threading.Thread(target=run_server, args=(port,), daemon=True)
    server_thread.start()

    if not wait_for_server(port):
        print("SERVER FAILED TO START — port never came up", file=sys.stderr)
        sys.exit(1)

    if args.self_test:
        import urllib.request

        frontend_ok = False
        if warning is None:
            body = urllib.request.urlopen(f"http://127.0.0.1:{port}/", timeout=2).read()
            frontend_ok = b"PcTuner-Open-Source" in body

        print(f"SELFTEST OK — server up on 127.0.0.1:{port}, frontend mounted: {warning is None}")
        if warning is None and not frontend_ok:
            print("SELFTEST FAILED — static mount served a response but it wasn't the app", file=sys.stderr)
            sys.exit(1)
        return

    import webview

    window = webview.create_window(
        WINDOW_TITLE,
        f"http://127.0.0.1:{port}/",
        width=1180,
        height=840,
        min_size=(920, 600),
        background_color="#09090E",
    )
    # func runs in a background thread once the GUI loop is live (pywebview's
    # documented pattern for post-creation work) — _bring_to_front needs the
    # window already shown before FindWindowW can locate its hwnd.
    webview.start(_bring_to_front, (window,))


if __name__ == "__main__":
    main()
