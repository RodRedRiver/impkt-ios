import { createFileRoute, Link } from "@tanstack/react-router";
import { Check, ChevronRight, Pencil, X } from "lucide-react";
import { useEffect, useState } from "react";
import {
  computeStats,
  fmt,
  fmtDuration,
  groupSessions,
  loadSessions,
  renameSession,
  sessionTitle,
  type Session,
} from "@/lib/impkt";

export const Route = createFileRoute("/history")({
  head: () => ({
    meta: [
      { title: "History — IMPKT boxing sessions" },
      {
        name: "description",
        content: "Every saved boxing session grouped by week and month, with fatigue and volume.",
      },
      { property: "og:title", content: "History — IMPKT boxing sessions" },
      {
        property: "og:description",
        content: "Review boxing sessions over time: duration, fatigue and punch count.",
      },
    ],
  }),
  component: HistoryPage,
});

function HistoryPage() {
  const [sessions, setSessions] = useState<Session[]>([]);
  const [editing, setEditing] = useState<string | null>(null);
  const [draft, setDraft] = useState("");

  useEffect(() => setSessions(loadSessions()), []);

  const startRename = (s: Session) => {
    setEditing(s.id);
    setDraft(s.title ?? "");
  };

  const commit = (id: string) => {
    setSessions(renameSession(id, draft));
    setEditing(null);
  };

  const groups = groupSessions(sessions);

  return (
    <div className="px-5 pt-14">
      <h1 className="display text-5xl">History</h1>

      {sessions.length === 0 ? (
        <div className="glass mt-6 p-8 text-center text-sm text-muted-foreground">
          No saved sessions yet.
        </div>
      ) : (
        groups.map((g) => (
          <section key={g.label} className="mt-6">
            <div className="label-xs mb-2">{g.label}</div>
            <div className="space-y-2.5">
              {g.items.map((s) => {
                const st = computeStats(s.punches, s.endedAt - s.startedAt);
                const meta = `${fmtDuration(st.durationMs)} · ${st.punches} punches · ${
                  st.fatigueReady ? `${fmt(st.fatigue)}% fatigue` : "fatigue —"
                }`;

                if (editing === s.id) {
                  return (
                    <div key={s.id} className="glass px-4 py-3.5">
                      <label className="label-xs" htmlFor={`name-${s.id}`}>
                        Session name
                      </label>
                      <input
                        id={`name-${s.id}`}
                        autoFocus
                        value={draft}
                        onChange={(e) => setDraft(e.target.value)}
                        onKeyDown={(e) => {
                          if (e.key === "Enter") commit(s.id);
                          if (e.key === "Escape") setEditing(null);
                        }}
                        placeholder={sessionTitle(s)}
                        maxLength={48}
                        className="mt-1.5 w-full rounded-xl border border-border bg-transparent px-3 py-2 text-sm outline-none focus:border-primary"
                      />
                      <div className="mt-2 flex gap-2">
                        <button
                          onClick={() => commit(s.id)}
                          className="press flex flex-1 items-center justify-center gap-1.5 rounded-full bg-primary py-2.5 text-sm font-medium text-primary-foreground"
                        >
                          <Check className="h-4 w-4" /> Save
                        </button>
                        <button
                          onClick={() => setEditing(null)}
                          className="press flex flex-1 items-center justify-center gap-1.5 rounded-full border border-border py-2.5 text-sm font-medium text-muted-foreground"
                        >
                          <X className="h-4 w-4" /> Cancel
                        </button>
                      </div>
                    </div>
                  );
                }

                return (
                  <div key={s.id} className="glass flex items-center gap-1 px-4 py-3.5">
                    <Link
                      to="/history/$id"
                      params={{ id: s.id }}
                      className="flex min-w-0 flex-1 items-center gap-3"
                    >
                      <div className="min-w-0 flex-1">
                        <div className="truncate text-sm font-medium">{sessionTitle(s)}</div>
                        <div className="tnum mt-0.5 text-xs text-muted-foreground">{meta}</div>
                      </div>
                      <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
                    </Link>
                    <button
                      onClick={() => startRename(s)}
                      aria-label={`Rename ${sessionTitle(s)}`}
                      className="press ml-1 shrink-0 rounded-full border border-border p-2 text-muted-foreground"
                    >
                      <Pencil className="h-3.5 w-3.5" />
                    </button>
                  </div>
                );
              })}
            </div>
          </section>
        ))
      )}
    </div>
  );
}
