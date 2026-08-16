import { useEffect, useState } from "react";
import { api, type ToolKey, type ToolsResponse } from "./api";
import { AssistantWidget } from "./layout/AssistantWidget";
import { BackgroundGlows } from "./layout/BackgroundGlows";
import { HubView } from "./views/HubView";
import { ToolView } from "./views/ToolView";

type View = { name: "hub" } | { name: "tool"; toolKey: ToolKey };

/** Hand-rolled router (§6.6) — only 2 route shapes and a chromeless window,
 * so a plain view state machine beats pulling in react-router for nothing. */
function App() {
  const [view, setView] = useState<View>({ name: "hub" });
  const [toolsData, setToolsData] = useState<ToolsResponse | null>(null);
  const [toolsError, setToolsError] = useState<string | null>(null);
  const [healthWarning, setHealthWarning] = useState<string | null>(null);
  const [version, setVersion] = useState<string | null>(null);
  const [scanningPc, setScanningPc] = useState(false);
  const [scanPcError, setScanPcError] = useState<string | null>(null);

  useEffect(() => {
    api
      .tools()
      .then(setToolsData)
      .catch((e) => setToolsError(e.message ?? "failed to load"));
    api
      .health()
      .then((h) => setHealthWarning(h.ok ? null : "PowerShell not found"))
      // A failure HERE (network error, backend not actually up yet, ...) is
      // a more severe case than "PowerShell not found" — silently
      // swallowing it meant the one banner meant to catch backend problems
      // never fires for the backend being unreachable at all.
      .catch(() =>
        setHealthWarning("Couldn't reach the backend — try restarting the app"),
      );
    api
      .version()
      .then((v) => setVersion(v.version))
      .catch(() => {});
  }, []);

  const scanPc = async () => {
    setScanningPc(true);
    setScanPcError(null);
    try {
      const inventory = await api.scanPc();
      setToolsData((prev) =>
        prev ? { ...prev, specs: inventory.Specs } : prev,
      );
    } catch (e) {
      setScanPcError(e instanceof Error ? e.message : "scan failed");
    } finally {
      setScanningPc(false);
    }
  };

  return (
    <>
      <BackgroundGlows />
      {view.name === "hub" ? (
        <HubView
          data={toolsData}
          error={toolsError}
          healthWarning={healthWarning}
          version={version}
          onLaunch={(toolKey) => setView({ name: "tool", toolKey })}
          onScanPc={scanPc}
          scanningPc={scanningPc}
          scanPcError={scanPcError}
        />
      ) : (
        <ToolView
          tool={view.toolKey}
          specs={toolsData?.specs ?? null}
          onBack={() => setView({ name: "hub" })}
        />
      )}
      <AssistantWidget />
    </>
  );
}

export default App;
