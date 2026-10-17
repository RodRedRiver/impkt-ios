import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { ChevronRight, X } from "lucide-react";
import { PowerCurve } from "@/components/PowerCurve";
import {
  computeStats,
  fmt,
  fmtDuration,
  fmtTime,
  insight,
  loadSessions,
  power,
  powerCurve,
  type Punch,
  punchLabel,
  type Session,
} from "@/lib/impkt";

type Search = { id?: string | undefined };

export const Route = createFileRoute("/summary")({
  validateSearch: (s: Record<string, unknown>): Search => ({
    id: typeof s["id"] === "string" ? (s["id"] as string) : undefined,
  }),
  head: () => ({
    meta: [
      { title: "Session summary — IMPKT" },
      {
        name: "description",
        content:
          "Post-session summary: peak g, best power, total punches and a tappable punch-by-punch rail.",
      },
      { property: "og:title", content: "Session summary — IMPKT" },
      {
        property: "og:description",
        content: "Peak g, best power, total punches and punch-by-punch detail.",
      },
    ],
  }),
  component: SummaryPage,
});


const CLIP_G = 16;

function SummaryPage() {
  const { id } = Route.useSearch();
  const navigate = useNavigate();
  const [session, setSession] = useState<Session | null>(null);
  const [prior, setPrior] = useState<number[]>([]);
  const [ready, setReady] = useState(false);
  const [detail, setDetail] = useState<number | null>(null);

  useEffect(() => {
    const all = loadSessions();
    const found = (id ? all.find((s) => s.id === id) : all[0]) ?? all[0] ?? null;
    setSession(found);
    setPrior(
      all
        .filter((s) => s.id !== found?.id)
        .slice(0, 5)
        .map((s) => computeStats(s.punches, s.endedAt - s.startedAt))
        .filter((s) => s.fatigueReady)
        .map((s) => s.fatigue),
    );
    setReady(true);
  }, [id]);

  if (!ready) {
    return <div className="px-5 pt-14 text-sm text-muted-foreground">Loading…</div>;
  }

  if (!session) {
    return (
      <div className="px-5 pt-14">
        <h1 className="display text-5xl">Summary</h1>
        <div className="glass mt-6 p-8 text-center">
          <p className="text-sm text-muted-foreground">
            No session to summarise yet. Record one and it lands here automatically.
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
  const peakG = session.punches.reduce((m, p) => Math.max(m, p.peakG), 0);
  const clipped = session.punches.filter((p) => p.peakG >= CLIP_G).length;
  const railMax = Math.max(1, ...session.punches.map(power));
  const selected = detail !== null ? session.punches[detail] : undefined;

  return (
    <div className="px-5 pb-4 pt-14">
      <div className="label-xs">Session complete · saved automatically</div>
      <h1 className="display mt-2 text-[42px]">Summary</h1>
      <p className="text-sm text-muted-foreground">
        {fmtTime(session.startedAt)} · {fmtDuration(st.durationMs)}
      </p>

      <div className="glass glass-hero mt-6 px-8 py-9 text-center">
        <div className="label-xs">Total punches</div>
        <div className="display tnum mt-3 text-[86px] leading-[0.9]">{st.punches}</div>
        <p className="mx-auto mt-3 max-w-[19rem] text-[13px] leading-relaxed text-muted-foreground">
          {insight(st, prior)}
        </p>
      </div>

      <div className="mt-3 grid grid-cols-2 gap-2.5">
        <div className="glass px-5 py-4">
          <div className="label-xs">Peak g</div>
          <div className="display tnum mt-1.5 text-[34px] text-primary">
            {fmt(Math.min(peakG, CLIP_G), 1)}
            <span className="ml-1 text-sm font-medium text-muted-foreground">g</span>
          </div>
          <div className="mt-0.5 text-[11px] text-muted-foreground">
            {clipped > 0 ? `${clipped} reading${clipped > 1 ? "s" : ""} clipped at ${CLIP_G} g` : `Sensor range 0–${CLIP_G} g`}
          </div>
        </div>
        <div className="glass px-5 py-4">
          <div className="label-xs">Best power</div>
          <div className="display tnum mt-1.5 text-[34px]">{fmt(st.bestPower)}</div>
          <div className="mt-0.5 text-[11px] text-muted-foreground">
            Avg {fmt(st.avgPower)} · {fmt(st.tempo, 1)} p/min
          </div>
        </div>
      </div>

      <div className="glass mt-3 p-4">
        <PowerCurve values={powerCurve(session.punches)} label="Power across the session" />
      </div>

      {/* Punch rail — tap a punch for detail */}
      <div className="glass mt-3 p-4">
        <div className="mb-3 flex items-center justify-between">
          <div className="label-xs">Punch by punch</div>
          <span className="text-[11px] text-muted-foreground">Tap a bar</span>
        </div>
        <div className="flex h-24 items-end gap-[3px] overflow-x-auto pb-1">
          {session.punches.map((p, i) => (
            <button
              key={i}
              onClick={() => setDetail(i)}
              aria-label={`Punch ${i + 1}, ${punchLabel(p)}`}
              className="group h-full min-w-[7px] flex-none rounded-full bg-transparent"
            >
              <span className="flex h-full w-full items-end">
                <span
                  className={
                    "block w-full rounded-full transition-colors " +
                    (detail === i ? "bg-primary" : "bg-primary/45 group-hover:bg-primary/70")
                  }
                  style={{ height: `${Math.max(8, (power(p) / railMax) * 100)}%` }}
                />
              </span>
            </button>
          ))}
        </div>
      </div>

      <div className="mt-4 flex gap-2.5">
        <Link
          to="/session"
          className="press flex flex-1 items-center justify-center gap-1 rounded-full border border-border py-4 text-sm font-medium"
        >
          Full breakdown <ChevronRight className="h-4 w-4" />
        </Link>
        <button
          onClick={() => navigate({ to: "/" })}
          className="press flex-1 rounded-full bg-primary py-4 text-sm font-semibold text-primary-foreground"
        >
          Done
        </button>
      </div>

      {selected && (
        <div className="fixed inset-0 z-50 flex items-end justify-center sm:items-center">
          <button
            aria-label="Close"
            onClick={() => setDetail(null)}
            className="absolute inset-0 bg-black/55 backdrop-blur-[2px]"
          />
          <div
            role="dialog"
            aria-modal="true"
            aria-label="Punch detail"
            className="glass relative m-3 w-full max-w-[380px] p-5"
          >
            <button
              onClick={() => setDetail(null)}
              aria-label="Close"
              className="absolute right-4 top-4 text-muted-foreground"
            >
              <X className="h-4 w-4" />
            </button>
            <div className="label-xs">Punch {(detail ?? 0) + 1} of {st.punches}</div>
            <h2 className="display mt-1 text-[28px]">{punchLabel(selected)}</h2>
            <p className="text-[12px] text-muted-foreground">
              at {fmtDuration(selected.t)} into the session
            </p>
            <div className="mt-4 grid grid-cols-3 gap-2.5 text-center">
              <PunchStat label="Peak g" value={fmt(Math.min(selected.peakG, CLIP_G), 1)} />
              <PunchStat label="Velocity" value={fmt(selected.velocity, 1)} />
              <PunchStat label="Power" value={fmt(power(selected))} />
            </div>
            {selected.peakG >= CLIP_G && (
              <p className="mt-3 text-[12px] text-primary">
                Clipped — this punch exceeded the sensor's {CLIP_G} g range.
              </p>
            )}
            <div className="mt-4 flex gap-2">
              <NavBtn
                label="Previous"
                disabled={(detail ?? 0) <= 0}
                onClick={() => setDetail((d) => Math.max(0, (d ?? 0) - 1))}
              />
              <NavBtn
                label="Next"
                disabled={(detail ?? 0) >= session.punches.length - 1}
                onClick={() =>
                  setDetail((d) => Math.min(session.punches.length - 1, (d ?? 0) + 1))
                }
              />
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function PunchStat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-2xl border border-border/60 px-2 py-3">
      <div className="label-xs">{label}</div>
      <div className="display tnum mt-1 text-[22px]">{value}</div>
    </div>
  );
}

function NavBtn({
  label,
  disabled,
  onClick,
}: {
  label: string;
  disabled: boolean;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className="press flex-1 rounded-full border border-border py-3 text-sm font-medium disabled:opacity-35"
    >
      {label}
    </button>
  );
}

export type { Punch };
