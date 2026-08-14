"""§8 frozen-mode path resolution — REPO_ROOT must switch from
"next to this file" (dev) to "next to the exe" (frozen) without anything
else in the module changing. paths.py computes REPO_ROOT at import time, so
these tests reload the module around a patched `sys.frozen`/`sys.executable`
and always reload back to the real dev-mode state afterward.
"""

import importlib
import sys
from pathlib import Path

from backend import paths as paths_module


def _reload():
    return importlib.reload(paths_module)


def test_dev_mode_repo_root_is_two_parents_up_from_this_file():
    mod = _reload()
    assert mod.REPO_ROOT == Path(mod.__file__).resolve().parents[2]
    assert (mod.REPO_ROOT / "shared").name == "shared"


def test_frozen_mode_repo_root_is_next_to_the_exe(monkeypatch, tmp_path):
    fake_exe = tmp_path / "PCTuner-Optimization-Tool.exe"
    fake_exe.touch()
    monkeypatch.setattr(sys, "frozen", True, raising=False)
    monkeypatch.setattr(sys, "executable", str(fake_exe))
    try:
        mod = _reload()
        assert mod.REPO_ROOT == tmp_path
        assert mod.SHARED_DIR == tmp_path / "shared"
        assert mod.CHANGES_DIR == tmp_path / "changes"
    finally:
        monkeypatch.undo()
        _reload()  # restore dev-mode REPO_ROOT for every other test module
