/** Client for PCTuner Assistant -- NOT one of this app's own /api/* routes
 * (see api.ts). This calls out to Minni.ai's hosted service directly,
 * cross-origin, from the desktop app's webview.
 *
 * Why not proxy through this app's own local backend.py: PCTuner ships as a
 * public .exe, so it can never safely hold a secret -- any key baked into
 * either layer (JS here, or the bundled Python backend) is extractable by
 * anyone who downloads the app. Minni's PCTuner Assistant route is public
 * and unauthenticated specifically for that reason (rate-limited per-IP
 * server-side instead), so calling it directly is the correct shape, not a
 * shortcut. */

const ASSISTANT_BASE_URL = "https://primeai-uvv4.onrender.com";
const ASSISTANT_PATH = "/api/v1/public/pctuner-assistant/chat";

export interface AssistantMessage {
  role: "user" | "assistant";
  content: string;
}

interface AssistantChatResponse {
  provider: string;
  text: string;
}

export async function sendAssistantMessage(
  message: string,
  history: AssistantMessage[],
): Promise<string> {
  const res = await fetch(`${ASSISTANT_BASE_URL}${ASSISTANT_PATH}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ message, history }),
  });
  if (!res.ok) {
    const body = await res.json().catch(() => null);
    throw new Error(body?.detail ?? `Request failed (${res.status})`);
  }
  const data = (await res.json()) as AssistantChatResponse;
  return data.text;
}
