import { Bell, CheckCheck, Sparkles, Timer, Info, X } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import {
  clearAlerts,
  dismissAlert,
  idleReminder,
  loadAlerts,
  markAllRead,
  markRead,
  pushAlerts,
  unreadCount,
  visibleAlerts,
  type Alert,
} from "@/lib/notifications";

const icons = { milestone: Sparkles, reminder: Timer, info: Info } as const;

function ago(ts: number) {
  const diff = Math.max(0, Date.now() - ts);
  const m = Math.round(diff / 60000);
  if (m < 1) return "just now";
  if (m < 60) return `${m}m ago`;
  const h = Math.round(m / 60);
  if (h < 24) return `${h}h ago`;
  return `${Math.round(h / 24)}d ago`;
}

export function NotificationCenter() {
  const [alerts, setAlerts] = useState<Alert[]>([]);
  const [open, setOpen] = useState(false);
  const bellRef = useRef<HTMLButtonElement>(null);
  const announced = useRef<Set<string>>(new Set());
  const primed = useRef(false);

  useEffect(() => {
    const sync = () => {
      const list = pushAlerts(idleReminder());
      setAlerts(list);
      // In-app alert for anything that just became due.
      for (const a of visibleAlerts(list)) {
        if (announced.current.has(a.id)) continue;
        announced.current.add(a.id);
        if (primed.current && !a.read) toast(a.title, { description: a.body });
      }
      primed.current = true;
    };
    sync();
    const id = setInterval(sync, 30000);
    window.addEventListener("focus", sync);
    return () => {
      clearInterval(id);
      window.removeEventListener("focus", sync);
    };
  }, []);

  const visible = visibleAlerts(alerts);
  const unread = unreadCount(alerts);

  return (
    <>
      <Button
        ref={bellRef}
        type="button"
        variant="ghost"
        onClick={() => setOpen(true)}
        aria-haspopup="dialog"
        aria-label={
          unread > 0 ? `Open notifications, ${unread} unread` : "Open notifications, none unread"
        }
        className="train-focus relative flex min-h-11 min-w-11 items-center justify-center rounded-full border border-white/90 bg-white/55 p-0 text-foreground/65 shadow-[0_8px_24px_-14px_rgba(36,42,52,0.35),inset_0_1px_0_white] backdrop-blur-2xl transition-transform active:scale-90"
      >
        <Bell className="h-[20px] w-[20px]" strokeWidth={1.6} />
        {unread > 0 && (
          <span className="absolute -right-0.5 -top-0.5 flex h-[18px] min-w-[18px] items-center justify-center rounded-full bg-primary px-1 text-[10px] font-bold tabular-nums text-primary-foreground">
            {unread > 9 ? "9+" : unread}
          </span>
        )}
      </Button>

      <Dialog
        open={open}
        onOpenChange={(next) => {
          setOpen(next);
          if (!next) window.requestAnimationFrame(() => bellRef.current?.focus());
        }}
      >
        <DialogContent
          onCloseAutoFocus={(e) => {
            e.preventDefault();
            bellRef.current?.focus();
          }}
          className="train-modal-glass bottom-3 left-1/2 top-auto w-[calc(100%-1.5rem)] max-w-[380px] -translate-x-1/2 translate-y-0 rounded-[28px] p-5 text-foreground sm:bottom-auto sm:top-1/2 sm:-translate-y-1/2"
        >
          <DialogTitle className="pr-12 text-[19px] font-semibold text-foreground">
            Notifications
          </DialogTitle>
          <DialogDescription className="text-[12px] text-muted-foreground">
            Goal milestones and post-workout reminders, kept on this device.
          </DialogDescription>

          {visible.length === 0 ? (
            <p className="train-modal-tile mt-2 rounded-2xl px-4 py-4 text-[13px] leading-snug text-muted-foreground">
              Nothing yet. Finish a session and your milestones will land here.
            </p>
          ) : (
            <>
              <ul className="mt-1 max-h-[46vh] space-y-2 overflow-y-auto pr-0.5">
                {visible.map((a) => {
                  const Icon = icons[a.kind];
                  return (
                    <li key={a.id}>
                      <div
                        className={`train-modal-tile relative flex gap-3 rounded-2xl px-4 py-3 ${
                          a.read ? "opacity-70" : ""
                        }`}
                      >
                        <Icon
                          className={`mt-0.5 h-4 w-4 shrink-0 ${
                            a.kind === "milestone" ? "text-primary" : "text-foreground/55"
                          }`}
                          strokeWidth={1.9}
                        />
                        <div className="min-w-0 flex-1">
                          <div className="flex items-center gap-2">
                            <span className="text-[14px] font-semibold text-foreground">
                              {a.title}
                            </span>
                            {!a.read && (
                              <span className="h-1.5 w-1.5 shrink-0 rounded-full bg-primary" />
                            )}
                          </div>
                          <p className="mt-0.5 text-[12px] leading-snug text-muted-foreground">
                            {a.body}
                          </p>
                          <div className="mt-1 flex items-center gap-3">
                            <span className="text-[11px] text-muted-foreground/80">
                              {ago(a.createdAt)}
                            </span>
                            {!a.read && (
                              <Button
                                type="button"
                                variant="ghost"
                                onClick={() => setAlerts(markRead(a.id))}
                                className="train-focus h-auto min-h-0 p-0 text-[11px] font-medium text-primary"
                              >
                                Mark read
                              </Button>
                            )}
                          </div>
                        </div>
                        <Button
                          type="button"
                          variant="ghost"
                          onClick={() => setAlerts(dismissAlert(a.id))}
                          aria-label={`Dismiss notification: ${a.title}`}
                          className="train-focus h-8 w-8 shrink-0 rounded-full p-0 text-muted-foreground"
                        >
                          <X className="h-4 w-4" />
                        </Button>
                      </div>
                    </li>
                  );
                })}
              </ul>

              <div className="mt-1 flex gap-2">
                <Button
                  type="button"
                  variant="ghost"
                  onClick={() => setAlerts(markAllRead())}
                  className="train-focus train-modal-tile flex min-h-11 flex-1 items-center justify-center gap-2 rounded-full px-4 text-[12px] font-semibold text-foreground"
                >
                  <CheckCheck className="h-4 w-4" /> Mark all read
                </Button>
                <Button
                  type="button"
                  variant="ghost"
                  onClick={() => setAlerts(clearAlerts())}
                  className="train-focus train-modal-tile min-h-11 rounded-full px-4 text-[12px] font-semibold text-foreground"
                >
                  Clear all
                </Button>
              </div>
            </>
          )}
        </DialogContent>
      </Dialog>
    </>
  );
}
