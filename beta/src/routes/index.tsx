import { createFileRoute, Link } from "@tanstack/react-router";
import { Bluetooth, Check, ChevronRight, Clock, Dumbbell, Loader2, Settings, Target } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { InstallPrompt } from "@/components/InstallPrompt";
import { NotificationCenter } from "@/components/NotificationCenter";
import { QuickSettings } from "@/components/QuickSettings";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogTitle,
} from "@/components/ui/dialog";
import { bandLabel, connectBand, disconnectBand, useBand } from "@/lib/band";
import { useSettings } from "@/lib/settings";
import {
  computeStats,
  fmt,
  fmtDay,
  fmtDuration,
  fmtTime,
  insight,
  loadSessions,
  sessionTitle,
  WORKOUTS,
} from "@/lib/impkt";
import bandImg from "@/assets/sensor-box.png";

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title: "Train — IMPKT boxing sensor app" },
      {
        name: "description",
        content:
          "Connect your IMP-01 wrist band, choose a workout and start recording a boxing session in one tap.",
      },
      { property: "og:title", content: "Train — IMPKT boxing sensor app" },
      {
        property: "og:description",
        content: "Connect the IMP-01 band and start recording a session.",
      },
    ],
  }),
  component: TrainPage,
});

function TrainPage() {
  const band = useBand();
  const [demo, setDemo] = useState(false);
  const [localNotice, setNotice] = useState<string | null>(null);
  const notice = band.message ?? localNotice;
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [modeOpen, setModeOpen] = useState(false);
  const [cardOpen, setCardOpen] = useState<"workout" | "goals" | "review" | null>(null);
  const workoutButtonRef = useRef<HTMLButtonElement>(null);
  const goalsButtonRef = useRef<HTMLButtonElement>(null);
  const reviewButtonRef = useRef<HTMLButtonElement>(null);
  const modeButtonRef = useRef<HTMLButtonElement>(null);
  const { settings, update } = useSettings();

  const closeCard = () => {
    const trigger = cardOpen === "workout"
      ? workoutButtonRef.current
      : cardOpen === "goals"
        ? goalsButtonRef.current
        : reviewButtonRef.current;
    setCardOpen(null);
    window.requestAnimationFrame(() => trigger?.focus());
  };

  const closeMode = () => {
    setModeOpen(false);
    window.requestAnimationFrame(() => modeButtonRef.current?.focus());
  };

  const connected = band.status === "connected";
  const connecting = band.status === "connecting";
  const paired = connected || demo;
  const activeDeviceId = connected ? (band.wraps[0]?.name ?? null) : null;

  // Every wrap that connects is remembered in Quick settings, under the name it advertises.
  const wrapNames = band.wraps.map((w) => w.name).join("|");
  useEffect(() => {
    if (!wrapNames) return;
    const names = wrapNames.split("|");
    const kept = settings.pairedDevices.filter((d) => !names.includes(d.id));
    update({ pairedDevices: [...kept, ...names.map((n) => ({ id: n, name: n, pairedAt: Date.now() }))] });
    setDemo(false);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [wrapNames]);

  const connect = async () => {
    setNotice(null);
    if (band.source === "none") {
      setDemo(true);
      setNotice("Bluetooth isn't available here — demo mode will simulate punches.");
      return;
    }
    await connectBand();
  };

  const disconnect = () => {
    setNotice(null);
    if (demo) setDemo(false);
    else void disconnectBand();
  };

  const statusText = connected || connecting
    ? bandLabel(band)
    : demo
      ? "Demo mode — punches simulated"
      : bandLabel(band);

  return (
    <div className="train-light-screen relative flex min-h-[100dvh] flex-col overflow-hidden px-5 pb-40 pt-6 text-foreground">
      <div aria-hidden className="pointer-events-none absolute inset-0 overflow-hidden">
        <div className="train-pearl-a animate-pearl-drift absolute -left-[24%] -top-[14%] h-[62%] w-[82%] rounded-full blur-2xl" />
        <div className="train-pearl-b animate-pearl-drift absolute -right-[28%] top-[24%] h-[56%] w-[72%] rounded-full blur-3xl [animation-delay:-8s]" />
        <div className="train-pearl-wash absolute inset-0" />
      </div>

      {/* Header */}
      <header className="relative flex items-center justify-between">
        <span
          className="font-wordmark text-[13px] font-light uppercase tracking-[0.5em] text-foreground/70"
        >
          IMPKT
        </span>
        <div className="flex items-center gap-2">
          <span className="mr-1 text-[11px] font-medium uppercase tracking-[0.28em] text-muted-foreground">
            Train
          </span>
          <NotificationCenter />
          <Button
            type="button"
            variant="ghost"
            onClick={() => setSettingsOpen(true)}
            aria-label="Open Train settings"
            className="train-focus relative flex min-h-11 min-w-11 items-center justify-center rounded-full border border-white/90 bg-white/55 p-0 text-foreground/65 shadow-[0_8px_24px_-14px_rgba(36,42,52,0.35),inset_0_1px_0_white] backdrop-blur-2xl transition-transform active:scale-90"
          >
            <Settings className="h-[20px] w-[20px]" strokeWidth={1.6} />
            <span className="absolute right-1.5 top-1.5 h-1.5 w-1.5 rounded-full bg-primary" />
          </Button>
        </div>
      </header>

      <QuickSettings
        open={settingsOpen}
        onClose={() => setSettingsOpen(false)}
        activeDeviceId={connected ? activeDeviceId : null}
        onRepair={(id) => {
          if (connected && id === activeDeviceId) {
            disconnect();
          } else {
            setSettingsOpen(false);
            void connect();
          }
        }}
      />

      {/* Connection label */}
      <Button
        type="button"
        variant="ghost"
        onClick={paired ? disconnect : connect}
        disabled={connecting}
        aria-label={paired ? `${statusText}. Disconnect device` : statusText}
        aria-busy={connecting}
        className="train-focus relative mx-auto mt-5 flex min-h-11 items-center gap-2 rounded-full border border-white/95 bg-white/62 px-4 py-2 text-[12px] font-medium text-foreground/70 shadow-[0_12px_30px_-18px_rgba(44,50,60,0.4),inset_0_1px_0_white] backdrop-blur-[28px] transition-all duration-300 hover:bg-white/82 hover:shadow-[0_14px_34px_-16px_rgba(44,50,60,0.42),inset_0_1px_0_white] active:scale-95"
      >
        {connecting ? (
          <Loader2 className="h-3.5 w-3.5 animate-spin" />
        ) : (
          <Bluetooth className="h-3.5 w-3.5 text-foreground/60" strokeWidth={2} />
        )}
        <span>{statusText}</span>
      </Button>

      {/* Sensor module hero with glass halo */}
      <div className="relative mx-auto mt-1 w-full max-w-[260px]">
        <div
          aria-hidden
          className="animate-halo absolute left-1/2 top-1/2 aspect-square w-[118%] -translate-x-1/2 -translate-y-1/2 rounded-full border border-white/90 bg-[radial-gradient(closest-side,rgba(255,255,255,0.88),rgba(228,232,238,0.42)_58%,transparent_74%)] shadow-[inset_0_0_44px_rgba(255,255,255,0.95),0_22px_70px_-34px_rgba(61,68,78,0.38)] backdrop-blur-[10px]"
        />
        <img
          src={bandImg}
          alt="Matte black IMPKT BOXING-01 sensor module with two magnetic pogo pins"
          width={1024}
          height={1024}
          className="mx-auto w-full drop-shadow-[0_26px_36px_rgba(40,45,55,0.28)]"
        />
      </div>

      <InstallPrompt />

      {notice && (
        <p
          role="status"
          className="relative mx-auto -mt-2 max-w-[300px] rounded-2xl border border-white/90 bg-white/58 px-4 py-2.5 text-center text-[12px] leading-snug text-muted-foreground shadow-[0_12px_30px_-22px_rgba(40,45,55,0.35),inset_0_1px_0_white] backdrop-blur-2xl"
        >
          {notice}
        </p>
      )}

      {/* Oversized title */}
      <h1 className="train-metal-text relative -mt-1 bg-clip-text text-center text-[60px] font-bold leading-none tracking-[0.08em] text-transparent [text-shadow:0_1px_0_rgba(255,255,255,0.9)]">
        TRAIN
      </h1>

      {/* Cards */}
      <div className="relative mx-auto mt-5 w-full max-w-[360px] space-y-2">
        <Button
          ref={workoutButtonRef}
          type="button"
          variant="ghost"
          onClick={() => setCardOpen("workout")}
          aria-haspopup="dialog"
          className="train-focus press group flex min-h-12 w-full items-center gap-3 rounded-2xl border border-white/95 bg-white/58 px-4 py-3 text-left shadow-[0_14px_38px_-24px_rgba(45,51,61,0.38),inset_0_1px_0_white,inset_0_-1px_0_rgba(133,140,152,0.08)] backdrop-blur-[30px] transition-all duration-300 hover:bg-white/82 hover:shadow-[0_18px_42px_-22px_rgba(45,51,61,0.42),inset_0_1px_0_white]"
        >
          <Dumbbell className="h-[18px] w-[18px] text-foreground/65" strokeWidth={1.7} />
          <span className="flex-1 text-[14px] font-medium text-foreground/80">
            Choose Workout: {settings.workout}
          </span>
          <ChevronRight className="h-4 w-4 text-muted-foreground/70" />
        </Button>
        <Button
          ref={goalsButtonRef}
          type="button"
          variant="ghost"
          onClick={() => setCardOpen("goals")}
          aria-haspopup="dialog"
          className="train-focus press group flex min-h-12 w-full items-center gap-3 rounded-2xl border border-white/95 bg-white/58 px-4 py-3 text-left shadow-[0_14px_38px_-24px_rgba(45,51,61,0.38),inset_0_1px_0_white,inset_0_-1px_0_rgba(133,140,152,0.08)] backdrop-blur-[30px] transition-all duration-300 hover:bg-white/82 hover:shadow-[0_18px_42px_-22px_rgba(45,51,61,0.42),inset_0_1px_0_white]"
        >
          <Target className="h-[18px] w-[18px] text-foreground/65" strokeWidth={1.7} />
          <span className="flex-1 text-[14px] font-medium text-foreground/80">Set Goals</span>
          <ChevronRight className="h-4 w-4 text-muted-foreground/70" />
        </Button>
        <Button
          ref={reviewButtonRef}
          type="button"
          variant="ghost"
          onClick={() => setCardOpen("review")}
          aria-haspopup="dialog"
          className="train-focus press group flex min-h-12 w-full items-center gap-3 rounded-2xl border border-white/95 bg-white/58 px-4 py-3 text-left shadow-[0_14px_38px_-24px_rgba(45,51,61,0.38),inset_0_1px_0_white,inset_0_-1px_0_rgba(133,140,152,0.08)] backdrop-blur-[30px] transition-all duration-300 hover:bg-white/82 hover:shadow-[0_18px_42px_-22px_rgba(45,51,61,0.42),inset_0_1px_0_white]"
        >
          <Clock className="h-[18px] w-[18px] text-foreground/65" strokeWidth={1.7} />
          <span className="flex-1 text-[14px] font-medium text-foreground/80">Review Last Session</span>
          <ChevronRight className="h-4 w-4 text-muted-foreground/70" />
        </Button>
      </div>

      {/* Card modals */}
      {cardOpen === "workout" && (
        <Sheet label="Choose workout" onClose={closeCard}>
          <div className="mt-4 space-y-2">
            {WORKOUTS.map((w) => {
              const active = settings.workout === w;
              return (
                <Button
                  type="button"
                  variant="ghost"
                  key={w}
                  onClick={() => {
                    update({ workout: w });
                    closeCard();
                  }}
                  aria-pressed={active}
                  className="train-focus train-modal-tile flex min-h-12 w-full items-center justify-between rounded-2xl px-4 py-3.5"
                >
                  <span className="text-[15px] font-medium text-foreground">{w}</span>
                  {active && <Check className="h-4 w-4 text-primary" strokeWidth={2.5} />}
                </Button>
              );
            })}
          </div>
        </Sheet>
      )}

      {cardOpen === "goals" && (
        <Sheet label="Set goals" onClose={closeCard}>
          <p className="mt-1 text-[12px] text-muted-foreground">
            Targets for each session. They're saved on this device.
          </p>
          <div className="mt-4 space-y-2">
            <GoalField
              label="Punches per session"
              value={settings.goals.punches}
              unit="punches"
              step={10}
              min={10}
              max={5000}
              onChange={(v) => update({ goals: { ...settings.goals, punches: v } })}
            />
            <GoalField
              label="Target tempo"
              value={settings.goals.tempo}
              unit="p/min"
              step={1}
              min={5}
              max={200}
              onChange={(v) => update({ goals: { ...settings.goals, tempo: v } })}
            />
          </div>
        </Sheet>
      )}

      {cardOpen === "review" && <LastSessionSheet onClose={closeCard} />}

      {/* Primary CTA */}
      <Button
        ref={modeButtonRef}
        type="button"
        variant="ghost"
        onClick={() => setModeOpen(true)}
        aria-haspopup="dialog"
        className="train-focus press animate-white-pulse relative mx-auto mt-5 flex min-h-14 w-full max-w-[360px] items-center justify-center overflow-hidden rounded-full border border-white bg-white/76 px-6 py-4 text-[15px] font-bold uppercase tracking-[0.12em] text-foreground/80 backdrop-blur-[30px] transition-transform duration-300 hover:scale-[1.015] hover:bg-white/95"
      >
        <span
          aria-hidden
          className="pointer-events-none absolute inset-x-2 top-[2px] h-[46%] rounded-full bg-[linear-gradient(180deg,rgba(255,255,255,0.98),rgba(255,255,255,0.12))]"
        />
        <span className="relative">Start Session</span>
      </Button>

      {/* Session mode chooser */}
      <Dialog open={modeOpen} onOpenChange={(open) => { if (!open) closeMode(); }}>
        <DialogContent onCloseAutoFocus={(event) => { event.preventDefault(); modeButtonRef.current?.focus(); }} className="train-modal-glass bottom-3 left-1/2 top-auto w-[calc(100%-1.5rem)] max-w-[380px] -translate-x-1/2 translate-y-0 rounded-[28px] p-5 text-foreground sm:bottom-auto sm:top-1/2 sm:-translate-y-1/2">
            <DialogTitle className="pr-12 text-[19px] font-semibold text-foreground">
              Choose session type
            </DialogTitle>
            <DialogDescription className="text-[12px] text-muted-foreground">
              Timed rounds with rest, or a free open session.
            </DialogDescription>
            <div className="space-y-2">
              <Link
                to="/record"
                search={{ mode: "rounds" }}
                className="train-focus train-modal-tile block min-h-14 rounded-2xl px-4 py-4 outline-none"
              >
                <span className="block text-[15px] font-semibold text-foreground">Rounds</span>
                <span className="mt-0.5 block text-[12px] text-muted-foreground">
                  3 × 3:00 with 1:00 rest between rounds
                </span>
              </Link>
              <Link
                to="/record"
                search={{ mode: "open" }}
                className="train-focus train-modal-tile block min-h-14 rounded-2xl px-4 py-4 outline-none"
              >
                <span className="block text-[15px] font-semibold text-foreground">Open session</span>
                <span className="mt-0.5 block text-[12px] text-muted-foreground">
                  Train freely — end whenever you're done
                </span>
              </Link>
            </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}

function Sheet({
  label,
  onClose,
  children,
}: {
  label: string;
  onClose: () => void;
  children: React.ReactNode;
}) {
  return (
    <Dialog open onOpenChange={(open) => { if (!open) onClose(); }}>
      <DialogContent className="train-modal-glass bottom-3 left-1/2 top-auto w-[calc(100%-1.5rem)] max-w-[380px] -translate-x-1/2 translate-y-0 rounded-[28px] p-5 text-foreground sm:bottom-auto sm:top-1/2 sm:-translate-y-1/2">
        <DialogTitle className="pr-12 text-[19px] font-semibold text-foreground">{label}</DialogTitle>
        {children}
      </DialogContent>
    </Dialog>
  );
}

function GoalField({
  label,
  value,
  unit,
  step,
  min,
  max,
  onChange,
}: {
  label: string;
  value: number;
  unit: string;
  step: number;
  min: number;
  max: number;
  onChange: (v: number) => void;
}) {
  return (
    <label className="train-modal-tile flex min-h-12 items-center justify-between gap-4 rounded-2xl px-4 py-3 focus-within:shadow-[0_0_0_3px_var(--color-primary)]">
      <span className="text-[13px] font-medium text-foreground/75">{label}</span>
      <span className="flex items-center gap-1.5">
        <input
          type="number"
          inputMode="numeric"
          step={step}
          min={min}
          max={max}
          value={value}
          onChange={(e) => {
            const n = Number(e.target.value);
            if (!Number.isNaN(n)) onChange(Math.min(max, Math.max(min, n)));
          }}
          aria-label={`${label}, ${unit}`}
          className="min-h-11 w-20 rounded-lg border border-white/90 bg-white/70 px-2 py-1 text-right text-[15px] font-semibold tabular-nums text-foreground shadow-[inset_0_1px_2px_oklch(0.4_0.01_255/0.08)] outline-none backdrop-blur-xl"
        />
        <span className="text-[12px] text-muted-foreground">{unit}</span>
      </span>
    </label>
  );
}

function LastSessionSheet({ onClose }: { onClose: () => void }) {
  const sessions = loadSessions();
  const last = sessions[0];

  return (
    <Sheet label="Last session" onClose={onClose}>
      {!last ? (
        <div className="mt-4">
          <p className="train-modal-tile rounded-2xl px-4 py-4 text-[13px] leading-snug text-muted-foreground">
            No sessions recorded yet. Start one and your results will show up here.
          </p>
        </div>
      ) : (
        (() => {
          const st = computeStats(last.punches, last.endedAt - last.startedAt);
          const prior = sessions.slice(1).map((s) =>
            computeStats(s.punches, s.endedAt - s.startedAt).fatigue,
          );
          return (
            <div className="mt-4 space-y-2">
              <div className="train-modal-tile rounded-2xl px-4 py-3">
                <div className="text-[15px] font-semibold text-foreground">{sessionTitle(last)}</div>
                <div className="mt-0.5 text-[12px] text-muted-foreground">
                  {fmtDay(last.startedAt)} · {fmtTime(last.startedAt)} · {fmtDuration(st.durationMs)}
                </div>
              </div>
              <div className="grid grid-cols-3 gap-2">
                {[
                  { label: "Punches", value: fmt(st.punches) },
                  { label: "Best power", value: fmt(st.bestPower) },
                  { label: "Tempo", value: `${fmt(st.tempo)}/min` },
                ].map((m) => (
                  <div
                    key={m.label}
                    className="train-modal-tile rounded-2xl px-3 py-3 text-center"
                  >
                    <div className="text-[10px] uppercase tracking-widest text-muted-foreground">
                      {m.label}
                    </div>
                    <div className="mt-1 text-[18px] font-semibold tabular-nums text-foreground">
                      {m.value}
                    </div>
                  </div>
                ))}
              </div>
              <p className="train-modal-tile rounded-2xl px-4 py-3 text-[12px] leading-snug text-foreground/70">
                {insight(st, prior)}
              </p>
              <Link
                to="/summary"
                search={{ id: last.id }}
                className="train-focus train-modal-tile block min-h-12 rounded-full px-6 py-3 text-center text-[13px] font-bold uppercase tracking-[0.12em] text-foreground outline-none"
              >
                Full summary
              </Link>
            </div>
          );
        })()
      )}
    </Sheet>
  );
}
