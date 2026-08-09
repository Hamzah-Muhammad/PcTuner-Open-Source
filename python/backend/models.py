"""Pydantic models mirroring the JSON already emitted by the PS engine (§4).

Field names stay PascalCase to match the wire format the 60+ PS scripts,
manifest.json files, and existing report JSON already use — introducing a
snake_case/alias translation layer here would just be friction for no
reader benefit, since nothing in this codebase's JSON is snake_case.
"""

from typing import Literal

from pydantic import BaseModel

ToolKey = Literal["fps", "startup"]
ScanStatus = Literal["APPLIED", "PENDING", "REVIEW", "SKIPPED", "ERROR"]


class PCSpecs(BaseModel):
    CPU: str
    Cores: str
    GPU: str
    RAM: str
    OS: str
    Disks: str
    NIC: str
    Elevated: bool | None = None


class ToolMeta(BaseModel):
    Key: ToolKey
    Name: str
    Tag: str
    Desc: str
    Meta: str


class CatalogItem(BaseModel):
    Id: str
    Level: int
    Module: str
    Name: str
    Desc: str
    Target: str
    DefaultChecked: bool
    ScriptPath: str | None = None
    ScriptArgs: dict[str, str] = {}


class ScanRequest(BaseModel):
    checked: list[str]


class ScanResult(BaseModel):
    Id: str
    Name: str
    Status: ScanStatus
    Current: str
    Target: str


class ApplyRequest(BaseModel):
    checked: list[str]


class ApplyItemResult(BaseModel):
    Id: str
    Mode: Literal["Apply"] = "Apply"
    Success: bool
    PreviouslyExisted: bool | None = None
    PreviousValue: object | None = None
    Note: str | None = None
    Error: str | None = None


class UndoItemResult(BaseModel):
    Id: str
    Mode: Literal["Undo"] = "Undo"
    Success: bool
    Note: str | None = None
    Error: str | None = None


class ApplyRunResult(BaseModel):
    """Wraps the per-item results with whether the promised System Restore
    Point actually got created — previously that failure was caught and
    silently discarded (§8.5's restore point is a coarse safety net on top
    of the undo log, but the confirm modal tells the user it "will be
    created first", so a silent failure there is a broken promise, not a
    harmless one)."""

    Results: list[ApplyItemResult]
    RestorePointOk: bool
    RestorePointNote: str | None = None


class InstalledSoftwareItem(BaseModel):
    Name: str
    Version: str


class RunningProcess(BaseModel):
    Name: str
    Pid: int


class SystemInventory(BaseModel):
    ScannedAt: str
    Specs: PCSpecs
    InstalledSoftware: list[InstalledSoftwareItem]
    RunningProcesses: list[RunningProcess]
