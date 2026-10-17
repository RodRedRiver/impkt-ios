import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { Breakdown } from "@/components/Breakdown";
import { Metric } from "@/components/Glass";
import { PowerCurve } from "@/components/PowerCurve";
import {
  computeStats,
  deleteSession,
  fmt,
  fmtDay,
  fmtDuration,
  fmtTime,
  insight,
  loadSessions,
  powerCurve,
  type Session,
} from "@/lib/impkt";

export const Route = createFileRoute("/session")({
  head: () => ({
    meta: [
      { title: "Latest session — IMPKT" },
      {
        name: "description",
        content: "Your latest boxing session: punch count, output, power, accuracy and fatigue.",
      },
      { property: "og:title", content: "Latest session — IMPKT" },
      {
        property: "og:description",
        content: "Punch count, output score, power, accuracy and fatigue for your last session.",
      },
    ],
  }),
  component: SessionPage,
});


function SessionPage() {
  const navigate = useNavigate();
  const [session, setSession] = useState<Session | null>(null);
  const [prior, setPrior] = useState<number[]>([]);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    const all = loadSessions();
    setSession(all[0] ?? null);
    setPrior(
      all
        .slice(1, 6)
        .map((s) => computeStats(s.punches, s.endedAt - s.startedAt))
        .filter((s) => s.fatigueReady)
        .map((s) => s.fatigue),
    );
    setReady(true);
  }, []);

  if (!ready) return <div className="px-4 pt-10 text-sm text-muted-foreground">Loading…</div>;

  if (!session) {
    return (
      <div className="px-5 pt-14">
        <h1 className="display text-5xl">Session</h1>
        <div className="glass mt-6 p-8 text-center">
          <p className="text-sm text-muted-foreground">
            No sessions yet. Record one and its summary lands here automatically.
          </p>
          <Link
            to="/"
            className="press mt-5 inline-flex rounded-full bg-primary px-5 py-2.5 text-sm font-medium text-primary-foreground"
          >
            Go to Train
          </Link>
        </div>
      </div>
    );
  }

  const st = computeStats(session.punches, session.endedAt - session.startedAt);

  return (
    <div className="px-5 pt-14">
      <div className="label-xs">Saved automatically</div>
      <h1 className="display mt-2 text-[42px]">
        {fmtDay(session.startedAt)}
      </h1>
      <p className="text-sm text-muted-foreground">
        {fmtTime(session.startedAt)} · {fmtDuration(st.durationMs)}
      </p>

      <div className="glass glass-hero mt-6 px-8 py-10 text-center">
        <div className="label-xs">Fatigue</div>
        <div className="display tnum mt-3 text-[92px] leading-[0.9] text-primary">
          {st.fatigueReady ? `${fmt(st.fatigue)}%` : "—"}
        </div>
        <p className="mx-auto mt-3 max-w-[19rem] text-[13px] leading-relaxed text-muted-foreground">
          {insight(st, prior)}
        </p>
      </div>

      <div className="glass mt-3 flex items-end justify-between p-6">
        <div>
          <div className="label-xs">Punches</div>
          <div className="display tnum text-[60px] leading-[0.9]">{st.punches}</div>
        </div>
        <div className="text-right">
          <div className="label-xs">Output</div>
          <div className="display tnum text-4xl">{fmt(st.output)}</div>
        </div>
      </div>

      <div className="mt-3 grid grid-cols-3 gap-2.5">
        <Metric label="Power" value={fmt(st.avgPower)} />
        <Metric label="Accuracy" value={`${fmt(st.accuracy)}%`} hint="Provisional" />
        <Metric label="Tempo" value={fmt(st.tempo, 1)} hint="P/min" />
      </div>


      <div className="glass mt-3 p-4">
        <PowerCurve values={powerCurve(session.punches)} label="Power across the session" />
      </div>

      <Breakdown st={st} />

      <button
        onClick={() => {
          deleteSession(session.id);
          navigate({ to: "/" });
        }}
        className="mt-4 w-full rounded-full border border-border py-4 text-sm font-medium text-muted-foreground"
      >
        Discard session
      </button>
    </div>
  );
}
