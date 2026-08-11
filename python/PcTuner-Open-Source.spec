# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller onefile spec (§8/§8.8). Bundles frontend/dist/ INSIDE the exe
(extracted to _MEIPASS at runtime — app.py's frozen FRONTEND_DIST branch
points here). Deliberately does NOT bundle shared/, changes/,
FPSOptimization/, StartupOptimization/ — those ship as real sibling folders
next to the exe in the release zip, since subprocess needs actual files on
disk to hand pwsh/powershell, not PyInstaller's extracted-per-run temp dir.

Run from python/: `pyinstaller PcTuner-Open-Source.spec --noconfirm`
Output: python/dist/PcTuner-Open-Source.exe (bare — won't run standalone until the
sibling .ps1 folders are copied alongside it, same caveat the ps2exe build
already carries).
"""

import re
from pathlib import Path

ROOT = Path(SPECPATH)  # noqa: F821 — injected by PyInstaller

version_text = (ROOT / "backend" / "__version__.py").read_text(encoding="utf-8")
VERSION = re.search(r'__version__\s*=\s*"([^"]+)"', version_text).group(1)
VERSION_NUMERIC = re.match(r"(\d+)\.(\d+)\.(\d+)", VERSION)
FILEVERS = tuple(int(g) for g in VERSION_NUMERIC.groups()) + (0,) if VERSION_NUMERIC else (0, 0, 0, 0)

VERSION_INFO_PATH = ROOT / "version_info.txt"
VERSION_INFO_PATH.write_text(
    "VSVersionInfo(\n"
    "  ffi=FixedFileInfo(\n"
    f"    filevers={FILEVERS!r},\n"
    f"    prodvers={FILEVERS!r},\n"
    "    mask=0x3f,\n"
    "    flags=0x0,\n"
    "    OS=0x40004,\n"
    "    fileType=0x1,\n"
    "    subtype=0x0,\n"
    "    date=(0, 0),\n"
    "  ),\n"
    "  kids=[\n"
    "    StringFileInfo(\n"
    "      [\n"
    "        StringTable(\n"
    "          '040904B0',\n"
    "          [\n"
    "            StringStruct('CompanyName', 'Hamzah Muhammad (@Humzeeny)'),\n"
    "            StringStruct('FileDescription', 'PcTuner-Open-Source — Windows optimization suite'),\n"
    f"            StringStruct('FileVersion', {VERSION!r}),\n"
    "            StringStruct('InternalName', 'PcTuner-Open-Source'),\n"
    "            StringStruct('OriginalFilename', 'PcTuner-Open-Source.exe'),\n"
    "            StringStruct('ProductName', 'PcTuner-Open-Source'),\n"
    f"            StringStruct('ProductVersion', {VERSION!r}),\n"
    "          ],\n"
    "        )\n"
    "      ]\n"
    "    ),\n"
    "    VarFileInfo([VarStruct('Translation', [1033, 1200])]),\n"
    "  ],\n"
    ")\n",
    encoding="utf-8",
)

a = Analysis(  # noqa: F821
    ["app.py"],
    pathex=[str(ROOT)],
    binaries=[],
    datas=[(str(ROOT / "frontend" / "dist"), "frontend_dist")],
    hiddenimports=[
        "uvicorn.logging",
        "uvicorn.loops",
        "uvicorn.loops.auto",
        "uvicorn.protocols",
        "uvicorn.protocols.http",
        "uvicorn.protocols.http.auto",
        "uvicorn.protocols.websockets",
        "uvicorn.protocols.websockets.auto",
        "uvicorn.lifespan",
        "uvicorn.lifespan.on",
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
)

pyz = PYZ(a.pure)  # noqa: F821

exe = EXE(  # noqa: F821
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name="PcTuner-Open-Source",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    version=str(VERSION_INFO_PATH),
    uac_admin=False,  # app.py manages elevation itself (§3.5) — a hard
    # requireAdministrator manifest would elevate before main() runs and
    # break unelevated `--self-test`.
)
