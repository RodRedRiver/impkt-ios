import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { ChevronLeft } from "lucide-react";
import { useEffect, useState } from "react";
import { Breakdown } from "@/components/Breakdown";
import { Metric } from "@/components/Glass";
import { PowerCurve } from "@/components/PowerCurve";
import {
  computeStats,
  deleteSession,
  fmt,
  sessionTitle,
  fmtDuration,
  fmtTime,
  loadSessions,
  powerCurve,
  type Session,
} from "@/lib/impkt";

export const Route = createFileRoute("/history/$id")({
  head: () => ({
    meta: [
      { title: "Session detail — IMPKT" },
      {
        name: "description",
        content: "Detailed metrics and power curve for a saved boxing session.",
      },
      { property: "og:title", content: "Session detail — IMPKT" },
      { property: "og:description", content: "Detailed metrics and power curve for a session." },
    ],
  }),
  component: SessionDetail,
});


function SessionDetail() {
  const { id } = Route.useParams();
  const navigate = useNavigate();
  const [session, setSession] = useState<Session | null>(null);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    setSession(loadSessions().find((s) => s.id === id) ?? null);
    setReady(true);
  }, [id]);

  if (!ready) return <div className="px-4 pt-10 text-sm text-muted-foreground">Loading…</div>;

  if (!session) {
    return (
      <div className="px-5 pt-14">
        <div className="glass p-8 text-center text-sm text-muted-foreground">
          This session no longer exists.
          <div>
            <Link to="/history" className="mt-4 inline-flex text-primary">
              Back to history
            </Link>
          </div>
        </div>
      </div>
    );
  }

  const st = computeStats(session.punches, session.endedAt - session.startedAt);

  return (
    <div className="px-5 pt-14">
      <Link to="/history" className="inline-flex items-center gap-1 text-sm text-muted-foreground">
        <ChevronLeft className="h-4 w-4" /> History
      </Link>
      <h1 className="display mt-3 text-[38px]">{sessionTitle(session)}</h1>
      <p className="text-sm text-muted-foreground">
        {fmtTime(session.startedAt)} · {fmtDuration(st.durationMs)}
      </p>

      <div className="mt-5 grid grid-cols-2 gap-2.5">
        <Metric label="Punches" value={st.punches} />
        <Metric label="Output" value={fmt(st.output)} accent />
        <Metric label="Power" value={fmt(st.avgPower)} hint={`Best ${fmt(st.bestPower)}`} />
        <Metric
          label="Fatigue"
          value={st.fatigueReady ? `${fmt(st.fatigue)}%` : "—"}
          hint={st.fatigueReady ? "Last quarter vs first" : "Needs 8+ punches"}
        />
        <Metric label="Accuracy" value={`${fmt(st.accuracy)}%`} hint="Provisional" />
        <Metric label="Tempo" value={fmt(st.tempo, 1)} hint="Punches / min" />
      </div>

      <div className="glass mt-3 p-4">
        <PowerCurve values={powerCurve(session.punches)} label="Power curve" height={140} />
      </div>

      <Breakdown st={st} />

      <button
        onClick={() => {
          deleteSession(session.id);
          navigate({ to: "/history" });
        }}
        className="mt-4 w-full rounded-full border border-border py-4 text-sm font-medium text-muted-foreground"
      >
        Delete session
      </button>
    </div>
  );
}
