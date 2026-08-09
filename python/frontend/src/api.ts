/** Typed fetch wrappers + shared types, mirroring python/backend/models.py 1:1
 * (§4/§6.6) — field names stay PascalCase to match the backend's wire format. */

export interface PCSpecs {
  CPU: string;
  Cores: string;
  GPU: string;
  RAM: string;
  OS: string;
  Disks: string;
  NIC: string;
  Elevated: boolean | null;
}

export type ToolKey = "fps" | "startup";

export interface ToolMeta {
  Key: ToolKey;
  Name: string;
  Tag: string;
  Desc: string;
  Meta: string;
}

export interface CatalogItem {
  Id: string;
  Level: number;
  Module: string;
  Name: string;
  Desc: string;
  Target: string;
  DefaultChecked: boolean;
  ScriptPath: string | null;
  ScriptArgs: Record<string, string>;
}

export type ScanStatus = "APPLIED" | "PENDING" | "REVIEW" | "SKIPPED" | "ERROR";

export interface ScanResult {
  Id: string;
  Name: string;
  Status: ScanStatus;
  Current: string;
  Target: string;
}

export interface ApplyItemResult {
  Id: string;
  Mode: "Apply";
  Success: boolean;
  PreviouslyExisted: boolean | null;
  PreviousValue: unknown;
  Note: string | null;
  Error: string | null;
}

export interface UndoItemResult {
  Id: string;
  Mode: "Undo";
  Success: boolean;
  Note: string | null;
  Error: string | null;
}

export interface ApplyRunResult {
  Results: ApplyItemResult[];
  RestorePointOk: boolean;
  RestorePointNote: string | null;
}

export interface InstalledSoftwareItem {
  Name: string;
  Version: string;
}

export interface RunningProcess {
  Name: string;
  Pid: number;
}

export interface SystemInventory {
  ScannedAt: string;
  Specs: PCSpecs;
  InstalledSoftware: InstalledSoftwareItem[];
  RunningProcesses: RunningProcess[];
}

export interface ToolsResponse {
  specs: PCSpecs | null;
  tools: ToolMeta[];
}

export interface HealthResponse {
  ok: boolean;
  ps_host_error: string | null;
}

export interface VersionResponse {
  version: string;
}

class ApiError extends Error {
  status: number;
  detail: string;

  constructor(status: number, detail: string) {
    super(detail);
    this.status = status;
    this.detail = detail;
  }
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(path, {
    ...init,
    headers: { "Content-Type": "application/json", ...init?.headers },
  });
  if (!res.ok) {
    const body = await res.json().catch(() => null);
    throw new ApiError(res.status, body?.detail ?? res.statusText);
  }
  return res.json() as Promise<T>;
}

export const api = {
  health: () => request<HealthResponse>("/api/health"),
  version: () => request<VersionResponse>("/api/version"),
  tools: () => request<ToolsResponse>("/api/tools"),
  catalog: (tool: ToolKey) => request<CatalogItem[]>(`/api/${tool}/catalog`),
  scan: (tool: ToolKey, checked: string[]) =>
    request<ScanResult[]>(`/api/${tool}/scan`, {
      method: "POST",
      body: JSON.stringify({ checked }),
    }),
  latestReport: (tool: ToolKey) =>
    request<{ path: string; results: ScanResult[] }>(
      `/api/${tool}/report/latest`,
    ),
  apply: (tool: ToolKey, checked: string[]) =>
    request<ApplyRunResult>(`/api/${tool}/apply`, {
      method: "POST",
      body: JSON.stringify({ checked }),
    }),
  undoAvailable: (tool: ToolKey) =>
    request<{ available: boolean; ageSeconds: number | null }>(
      `/api/${tool}/undo/available`,
    ),
  undo: (tool: ToolKey) =>
    request<UndoItemResult[]>(`/api/${tool}/undo`, { method: "POST" }),
  scanPc: () => request<SystemInventory>("/api/scan-pc", { method: "POST" }),
  getScanPc: () => request<SystemInventory | null>("/api/scan-pc"),
};

export { ApiError };
