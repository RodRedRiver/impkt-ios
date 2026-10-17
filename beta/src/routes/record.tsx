import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { Minimize2, Maximize2, Pause, Play } from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";
import { IntensityBars } from "@/components/PowerCurve";
import {
  computeStats,
  demoPunch,
  fmt,
  fmtDuration,
  power,
  saveSession,
  type Punch,
} from "@/lib/impkt";
import { bandLabel, onPunch, useBand } from "@/lib/band";
import { alertsForSession, pushAlerts } from "@/lib/notifications";
import { useSettings } from "@/lib/settings";

type Mode = "rounds" | "open";

const ROUND_MS = 3 * 60 * 1000;
const REST_MS = 60 * 1000;
const ROUNDS = 3;

export const Route = createFileRoute("/record")({
  validateSearch: (search: Record<string, unknown>): { mode: Mode } => ({
    mode: search["mode"] === "rounds" ? "rounds" : "open",
  }),
  head: () => ({
    meta: [
      { title: "Recording — IMPKT" },
      {
        name: "description",
        content: "Full-screen recording view with punch count, timer and live output metrics.",
      },
      { property: "og:title", content: "Recording — IMPKT" },
      { property: "og:description", content: "Live punch count, timer and session output." },
    ],
  }),
  component: RecordPage,
});

function RecordPage() {
  const navigate = useNavigate();
  const { settings } = useSettings();
  const band = useBand();
  const [punches, setPunches] = useState<Punch[]>([]);
  const [startedAt] = useState(() => Date.now());
  const [now, setNow] = useState(() => Date.now());
  const [minimal, setMinimal] = useState(false);
  const [paused, setPaused] = useState(false);
  const [pausedTotal, setPausedTotal] = useState(0);
  const pauseStart = useRef<number | null>(null);
  const { mode } = Route.useSearch();
  const punchesRef = useRef(punches);
  punchesRef.current = punches;
  // Live once the wraps are up, or once one has sent a punch: the app can hand over a
  // punch a moment before its next state report says the wrap is connected.
  const gotReal = punches.some((p) => p.score !== undefined);
  const live = band.status === "connected" || gotReal;

  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 250);
    return () => clearInterval(id);
  }, []);

  // Session clock excludes any paused time, so timers and stats stay honest.
  const elapsedAt = useCallback(
    (ts: number) => Math.max(0, (pauseStart.current ?? ts) - startedAt - pausedTotal),
    [startedAt, pausedTotal],
  );
  const elapsed = elapsedAt(now);

  const togglePause = () => {
    if (pauseStart.current === null) {
      pauseStart.current = Date.now();
      setPaused(true);
    } else {
      setPausedTotal((p) => p + (Date.now() - (pauseStart.current ?? Date.now())));
      pauseStart.current = null;
      setPaused(false);
    }
    setNow(Date.now());
  };


  // Rounds mode: derive current phase from elapsed time
  const cycle = ROUND_MS + REST_MS;
  const roundIdx = mode === "rounds" ? Math.min(ROUNDS, Math.floor(elapsed / cycle) + 1) : 0;
  const inRest =
    mode === "rounds" && elapsed % cycle >= ROUND_MS && roundIdx < ROUNDS;
  const roundsDone = mode === "rounds" && elapsed >= ROUNDS * cycle - REST_MS;
  const phaseRemaining =
    mode === "rounds"
      ? inRest
        ? cycle - (elapsed % cycle)
        : Math.max(0, ROUND_MS - (elapsed % cycle))
      : 0;

  const addPunch = useCallback(() => {
    if (pauseStart.current !== null) return; // capture is frozen while paused
    const t = elapsedAt(Date.now());
    setPunches((prev) => [...prev, demoPunch(t, Math.min(1, t / 600000))]);
  }, [elapsedAt]);

  // The real thing: every punch the wraps report while the clock is running. Timed
  // on arrival, which is within a link interval of when it landed.
  useEffect(
    () =>
      onPunch((bp) => {
        if (pauseStart.current !== null) return;
        const t = elapsedAt(Date.now());
        setPunches((prev) => [
          ...prev,
          { t, peakG: bp.peakG, velocity: bp.speed, score: bp.power, hand: bp.hand },
        ]);
      }),
    [elapsedAt],
  );

  useEffect(() => {
    if (live) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.code === "Space") {
        e.preventDefault();
        addPunch();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [addPunch, live]);

  const st = computeStats(punches, elapsed);

  const endRef = useRef<() => void>(() => {});
  useEffect(() => {
    if (mode === "rounds" && roundsDone && !paused) endRef.current();
  }, [mode, roundsDone, paused]);

  const end = () => {
    const list = punchesRef.current;
    if (list.length === 0) {
      navigate({ to: "/" });
      return;
    }
    // Duration excludes paused time so tempo and fatigue stay accurate.
    const endedAt = startedAt + elapsedAt(Date.now());
    const id = String(startedAt);
    const session = { id, startedAt, endedAt, punches: list };
    pushAlerts(alertsForSession(session, settings));
    saveSession(session);
    navigate({ to: "/summary", search: { id } });
  };
  endRef.current = end;

  return (
    <div className="flex min-h-[calc(100dvh-env(safe-area-inset-top))] flex-col px-5 pb-[max(2rem,env(safe-area-inset-bottom))] pt-12">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2 text-sm text-muted-foreground">
          <span
            className={`h-2 w-2 rounded-full ${paused ? "bg-muted-foreground" : "animate-pulse bg-primary"}`}
          />
          {paused
            ? "Paused"
            : mode === "rounds"
              ? roundsDone
                ? "Session complete"
                : inRest
                  ? `Rest · ${fmtDuration(phaseRemaining)}`
                  : `Round ${roundIdx}/${ROUNDS} · ${fmtDuration(phaseRemaining)}`
              : "Recording"}
        </div>
        <button
          onClick={() => setMinimal((m) => !m)}
          className="rounded-full border border-border p-2 text-muted-foreground"
          aria-label={minimal ? "Show full metrics" : "Switch to minimal view"}
        >
          {minimal ? <Maximize2 className="h-4 w-4" /> : <Minimize2 className="h-4 w-4" />}
        </button>
      </div>

      <div className="mt-8 text-center">
        <div className="display tnum text-[104px] leading-[0.86] tracking-[-0.02em]">{st.punches}</div>
        <div className="label-xs mt-1">Punches</div>
        <div className="tnum mt-5 text-2xl font-light tracking-[0.06em] text-muted-foreground">
          {fmtDuration(elapsed)}
        </div>
      </div>

      {minimal ? null : (
        <>
          <div className="mt-8 grid grid-cols-2 gap-2.5">
            <LiveStat label="Power" value={fmt(st.avgPower)} />
            <LiveStat
              label="Fatigue"
              value={st.fatigueReady ? `${fmt(st.fatigue)}%` : "—"}
              accent={st.fatigueReady && st.fatigue > 12}
            />
            <LiveStat label="Accuracy" value={`${fmt(st.accuracy)}%`} hint="Provisional" />
            <LiveStat label="Tempo" value={fmt(st.tempo)} hint="Punches / min" />
          </div>

          <div className="glass mt-3 p-4">
            <div className="label-xs mb-3">Recent intensity</div>
            <IntensityBars values={punches.map(power)} />
          </div>
        </>
      )}

      <div className="flex-1" />

      {live ? (
        <div className="glass mt-8 flex items-center justify-center gap-2 py-5 text-[15px] font-medium">
          <span className={`h-2 w-2 rounded-full ${paused ? "bg-muted-foreground" : "animate-pulse bg-primary"}`} />
          {bandLabel(band)}
        </div>
      ) : (
        <button
          onClick={addPunch}
          disabled={paused}
          className="mt-8 w-full rounded-full bg-primary py-5 text-[15px] font-medium tracking-wide text-primary-foreground press disabled:opacity-40"
        >
          {paused ? "Paused" : "Simulate punch"}
        </button>
      )}
      <p className="mt-2 text-center text-xs text-muted-foreground">
        {paused
          ? "Timers and punch capture are frozen — resume to continue."
          : live
            ? "Every punch from your wraps is recorded. Just hit the bag."
            : "No band connected, so these are demo punches. Connect your wraps on Train."}
      </p>

      <div className="mt-3 flex gap-2.5">
        <button
          onClick={togglePause}
          aria-pressed={paused}
          className="press flex flex-1 items-center justify-center gap-2 rounded-full border border-border py-4 text-sm font-medium"
        >
          {paused ? <Play className="h-4 w-4" /> : <Pause className="h-4 w-4" />}
          {paused ? "Resume" : "Pause"}
        </button>
        <button
          onClick={end}
          className="press flex-1 rounded-full border border-border py-4 text-sm font-medium"
        >
          End session
        </button>
      </div>
    </div>
  );
}

function LiveStat({
  label,
  value,
  hint,
  accent,
}: {
  label: string;
  value: string;
  hint?: string;
  accent?: boolean;
}) {
  return (
    <div className="glass px-4 py-3.5">
      <div className="label-xs">{label}</div>
      <div className={`display tnum mt-1 text-[28px] ${accent ? "text-primary" : ""}`}>
        {value}
      </div>
      {hint ? <div className="text-[11px] text-muted-foreground">{hint}</div> : null}
    </div>
  );
}
