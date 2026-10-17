import { useRouterState } from "@tanstack/react-router";
import { useCallback, useEffect, useRef } from "react";
import { toast } from "sonner";

const CHECK_INTERVAL_MS = 5 * 60 * 1000;
const TOAST_ID = "impkt-update-available";

async function fetchVersion(signal?: AbortSignal): Promise<string | null> {
  try {
    const res = await fetch("/api/public/version", { cache: "no-store", signal: signal ?? null });
    if (!res.ok) return null;
    const data = (await res.json()) as { version?: unknown };
    return typeof data.version === "string" ? data.version : null;
  } catch {
    return null;
  }
}

/**
 * Polls the deployed build id and offers a safe reload when a newer version
 * ships. Session history lives in localStorage, so reloading never loses data,
 * but we never interrupt an in-progress recording: the prompt waits until the
 * recording screen is left.
 */
export function UpdateWatcher() {
  const pathname = useRouterState({ select: (s) => s.location.pathname });
  const recording = pathname === "/record";

  const current = useRef<string | null>(null);
  const pending = useRef(false);
  const recordingRef = useRef(recording);
  recordingRef.current = recording;

  const promptReload = useCallback(() => {
    toast("A new version of IMPKT is ready", {
      id: TOAST_ID,
      description: "Your saved sessions stay safe. Reload to get the latest.",
      duration: Infinity,
      action: {
        label: "Reload",
        onClick: () => window.location.reload(),
      },
      cancel: {
        label: "Later",
        onClick: () => {},
      },
    });
  }, []);

  const check = useCallback(async (signal?: AbortSignal) => {
    const version = await fetchVersion(signal);
    if (!version) return;
    if (current.current === null) {
      current.current = version;
      return;
    }
    if (version !== current.current && !pending.current) {
      pending.current = true;
      if (!recordingRef.current) promptReload();
    }
  }, [promptReload]);

  useEffect(() => {
    const controller = new AbortController();
    void check(controller.signal);

    const interval = window.setInterval(() => {
      if (document.visibilityState === "visible") void check();
    }, CHECK_INTERVAL_MS);

    const onVisible = () => {
      if (document.visibilityState === "visible") void check();
    };
    document.addEventListener("visibilitychange", onVisible);
    window.addEventListener("focus", onVisible);

    return () => {
      controller.abort();
      window.clearInterval(interval);
      document.removeEventListener("visibilitychange", onVisible);
      window.removeEventListener("focus", onVisible);
    };
  }, [check]);

  // Update found mid-session: surface it once the recording screen is left.
  useEffect(() => {
    if (!recording && pending.current) promptReload();
  }, [recording, promptReload]);

  return null;
}
