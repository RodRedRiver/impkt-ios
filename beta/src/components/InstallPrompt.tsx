import { useEffect, useState } from "react";
import { Check, Download, MonitorSmartphone, Share, Smartphone, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import { IN_APP } from "@/lib/band";

const DISMISS_KEY = "impkt-install-dismissed";

type BeforeInstallPromptEvent = Event & {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: "accepted" | "dismissed" }>;
};

function isInstalled(): boolean {
  if (typeof window === "undefined") return false;
  const nav = navigator as Navigator & { standalone?: boolean };
  return (
    window.matchMedia("(display-mode: standalone)").matches ||
    window.matchMedia("(display-mode: window-controls-overlay)").matches ||
    nav.standalone === true
  );
}

function platform(): "ios" | "android" | "desktop" {
  const ua = navigator.userAgent;
  if (/iPhone|iPad|iPod/i.test(ua) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1)) return "ios";
  if (/Android/i.test(ua)) return "android";
  return "desktop";
}

export function InstallPrompt() {
  const [installed, setInstalled] = useState(true);
  const [deferred, setDeferred] = useState<BeforeInstallPromptEvent | null>(null);
  const [open, setOpen] = useState(false);
  const [dismissed, setDismissed] = useState(true);
  const [os, setOs] = useState<"ios" | "android" | "desktop">("desktop");

  useEffect(() => {
    // Inside the iOS app it is already installed, as an app.
    if (IN_APP || isInstalled()) return;
    setInstalled(false);
    setOs(platform());
    try {
      setDismissed(window.localStorage.getItem(DISMISS_KEY) === "1");
    } catch {
      setDismissed(false);
    }
    const onPrompt = (e: Event) => {
      e.preventDefault();
      setDeferred(e as BeforeInstallPromptEvent);
    };
    const onInstalled = () => setInstalled(true);
    window.addEventListener("beforeinstallprompt", onPrompt);
    window.addEventListener("appinstalled", onInstalled);
    return () => {
      window.removeEventListener("beforeinstallprompt", onPrompt);
      window.removeEventListener("appinstalled", onInstalled);
    };
  }, []);

  if (installed || dismissed) return null;

  const dismiss = () => {
    try {
      window.localStorage.setItem(DISMISS_KEY, "1");
    } catch {
      /* private mode */
    }
    setDismissed(true);
    setOpen(false);
  };

  const install = async () => {
    if (deferred) {
      await deferred.prompt();
      const choice = await deferred.userChoice;
      if (choice.outcome === "accepted") {
        setDeferred(null);
        dismiss();
      }
    } else {
      setOpen(true);
    }
  };

  return (
    <>
      <div
        role="region"
        aria-label="Install IMPKT"
        className="relative mx-auto mt-3 flex w-full max-w-[360px] items-center gap-3 rounded-2xl border border-white/95 bg-white/58 px-4 py-3 shadow-[0_14px_38px_-24px_rgba(45,51,61,0.38),inset_0_1px_0_white,inset_0_-1px_0_rgba(133,140,152,0.08)] backdrop-blur-[30px]"
      >
        <Download className="h-[18px] w-[18px] shrink-0 text-foreground/65" strokeWidth={1.7} aria-hidden />
        <div className="min-w-0 flex-1">
          <p className="text-[13px] font-semibold text-foreground/85">Install IMPKT</p>
          <p className="text-[11px] leading-snug text-muted-foreground">
            Add it to your home screen for one-tap sessions.
          </p>
        </div>
        <Button
          type="button"
          size="sm"
          onClick={install}
          aria-label={deferred ? "Install IMPKT now" : "Show how to install IMPKT"}
          className="train-focus min-h-11 rounded-full bg-primary px-4 text-[12px] font-semibold text-primary-foreground shadow-[0_10px_24px_-12px_rgba(160,13,45,0.55),inset_0_1px_0_rgba(255,255,255,0.28)] transition-transform active:scale-95"
        >
          {deferred ? "Install" : "How"}
        </Button>
        <Button
          type="button"
          variant="ghost"
          size="icon"
          onClick={dismiss}
          aria-label="Dismiss install prompt"
          className="train-focus -mr-1 min-h-11 min-w-11 rounded-full text-muted-foreground/70"
        >
          <X className="h-4 w-4" />
        </Button>
      </div>

      <Dialog open={open} onOpenChange={(v) => { if (!v) setOpen(false); }}>
        <DialogContent className="train-modal-glass bottom-3 left-1/2 top-auto w-[calc(100%-1.5rem)] max-w-[380px] -translate-x-1/2 translate-y-0 rounded-[28px] p-5 text-foreground sm:bottom-auto sm:top-1/2 sm:-translate-y-1/2">
          <DialogTitle className="text-[17px] font-semibold tracking-tight">Install IMPKT</DialogTitle>
          <DialogDescription className="text-[13px] text-muted-foreground">
            {os === "ios"
              ? "Install IMPKT on your iPhone or iPad so it opens full-screen from your home screen."
              : os === "android"
                ? "Install IMPKT on Android so it opens full-screen from your home screen."
                : "Install IMPKT on this computer so it opens in its own window."}
          </DialogDescription>

          <ol className="mt-4 space-y-2.5 text-[13px] text-foreground/85">
            {os === "ios" && (
              <>
                <Step n={1}>Tap the <Share className="mx-0.5 inline h-4 w-4 align-[-2px] text-foreground/70" aria-label="Share" /> <strong>Share</strong> button in Safari's toolbar.</Step>
                <Step n={2}>Scroll down and tap <strong>Add to Home Screen</strong>.</Step>
                <Step n={3}>Tap <strong>Add</strong> — IMPKT appears on your home screen.</Step>
              </>
            )}
            {os === "android" && (
              <>
                <Step n={1}>Tap the <strong>⋮ menu</strong> in Chrome.</Step>
                <Step n={2}>Tap <strong>Add to Home screen</strong> or <strong>Install app</strong>.</Step>
                <Step n={3}>Confirm — IMPKT appears on your home screen.</Step>
              </>
            )}
            {os === "desktop" && (
              <>
                <Step n={1}>Look for the <strong>install icon</strong> at the right end of the address bar.</Step>
                <Step n={2}>Or open the browser menu and choose <strong>Install IMPKT…</strong> (Chrome, Edge) or <strong>Add to Dock</strong> (Safari on Mac).</Step>
                <Step n={3}>Confirm — IMPKT opens in its own window.</Step>
              </>
            )}
          </ol>

          <div className="mt-4 flex items-center gap-2 rounded-2xl border border-white/90 bg-white/50 px-3.5 py-2.5 text-[12px] text-muted-foreground">
            <MonitorSmartphone className="h-4 w-4 shrink-0 text-foreground/60" aria-hidden />
            Installed, IMPKT keeps your sessions, goals and settings on this device.
          </div>

          <Button
            type="button"
            onClick={() => setOpen(false)}
            className="train-focus mt-4 min-h-11 w-full rounded-full bg-primary text-[13px] font-semibold text-primary-foreground shadow-[0_10px_24px_-12px_rgba(160,13,45,0.55),inset_0_1px_0_rgba(255,255,255,0.28)] active:scale-[0.98]"
          >
            <Check className="mr-1.5 h-4 w-4" aria-hidden /> Got it
          </Button>
          <Button
            type="button"
            variant="ghost"
            onClick={dismiss}
            className="train-focus mt-1.5 min-h-11 w-full rounded-full text-[12px] text-muted-foreground"
          >
            Don't show again
          </Button>
        </DialogContent>
      </Dialog>
    </>
  );
}

function Step({ n, children }: { n: number; children: React.ReactNode }) {
  return (
    <li className="flex items-start gap-2.5">
      <span
        aria-hidden
        className="mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full border border-white/95 bg-white/70 text-[11px] font-semibold text-foreground/70 shadow-[inset_0_1px_0_white]"
      >
        {n}
      </span>
      <span className="leading-snug">{children}</span>
    </li>
  );
}
