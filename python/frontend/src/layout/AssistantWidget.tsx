import { useEffect, useRef, useState } from "react";
import { sendAssistantMessage, type AssistantMessage } from "../assistant";
import { Button } from "../primitives/Button";
import styles from "./AssistantWidget.module.css";

const MAX_SENT_HISTORY = 12;

const GREETING: AssistantMessage = {
  role: "assistant",
  content:
    "Hi, I'm the PCTuner Assistant. Ask me what a checklist item does, whether it's safe to apply, or how Undo works.",
};

/** Floating chat widget, fixed to the bottom-right of the screen (§ user
 * request) and rendered once in App.tsx outside the Hub/Tool view switch, so
 * it persists across navigation instead of resetting per view. Mirrors
 * Minni.ai's own marketing-site ChatWidget.js pattern (toggle button +
 * expandable panel), ported to this app's red/black theme and CSS-module
 * convention instead of Minni's framer-motion + global CSS. */
export function AssistantWidget() {
  const [open, setOpen] = useState(false);
  const [messages, setMessages] = useState<AssistantMessage[]>([GREETING]);
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const listRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (listRef.current) {
      listRef.current.scrollTop = listRef.current.scrollHeight;
    }
  }, [messages, loading, open]);

  async function send(e: React.FormEvent) {
    e.preventDefault();
    const text = input.trim();
    if (!text || loading) return;

    const nextMessages = [...messages, { role: "user", content: text } as AssistantMessage];
    setMessages(nextMessages);
    setInput("");
    setLoading(true);
    setError(null);

    try {
      const history = nextMessages
        .slice(0, -1)
        .filter((m) => m !== GREETING)
        .slice(-MAX_SENT_HISTORY);
      const reply = await sendAssistantMessage(text, history);
      setMessages((cur) => [...cur, { role: "assistant", content: reply }]);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Something went wrong -- try again.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className={styles.widget}>
      {open && (
        <div className={styles.panel} role="dialog" aria-label="PCTuner Assistant">
          <div className={styles.panelHead}>
            <span className={styles.panelTitle}>PCTuner Assistant</span>
            <button
              type="button"
              className={styles.closeBtn}
              onClick={() => setOpen(false)}
              aria-label="Close assistant"
            >
              ×
            </button>
          </div>

          <div className={styles.messages} ref={listRef}>
            {messages.map((m, i) => (
              <div
                key={i}
                className={[styles.bubble, m.role === "assistant" ? styles.bubbleIn : styles.bubbleOut]
                  .filter(Boolean)
                  .join(" ")}
              >
                {m.content}
              </div>
            ))}
            {loading && (
              <div className={styles.typing} aria-live="polite">
                <span />
                <span />
                <span />
              </div>
            )}
            {error && <div className={styles.error}>{error}</div>}
          </div>

          <form className={styles.inputRow} onSubmit={send}>
            <input
              type="text"
              className={styles.input}
              placeholder="Ask about a checklist item…"
              value={input}
              onChange={(e) => setInput(e.target.value)}
              disabled={loading}
              maxLength={600}
              aria-label="Message"
            />
            <Button type="submit" variant="primary" disabled={loading || !input.trim()}>
              Send
            </Button>
          </form>
        </div>
      )}

      <button
        type="button"
        className={styles.toggle}
        onClick={() => setOpen((v) => !v)}
        aria-label={open ? "Close PCTuner Assistant" : "Open PCTuner Assistant"}
        aria-expanded={open}
      >
        {open ? "×" : "?"}
      </button>
    </div>
  );
}
