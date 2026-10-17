import { Provisional } from "@/components/Glass";
import { TYPE_LABEL, type PunchType, type SessionStats } from "@/lib/impkt";

/** The split under a session: by punch type for a demo session, by hand for a real one.
 *  The band measures which wrap threw a punch but not what kind of punch it was. */
export function Breakdown({ st }: { st: SessionStats }) {
  const total = st.punches || 1;
  const rows = st.typed
    ? (Object.keys(TYPE_LABEL) as PunchType[]).map((t) => ({
        key: t,
        label: TYPE_LABEL[t],
        n: st.byType[t],
      }))
    : [
        { key: "L", label: "Left", n: st.byHand.L },
        { key: "R", label: "Right", n: st.byHand.R },
      ];

  return (
    <div className="glass mt-3 p-4">
      <div className="mb-3 flex items-center justify-between">
        <div className="label-xs">{st.typed ? "By type" : "By hand"}</div>
        {st.typed ? <Provisional /> : null}
      </div>
      <div className="space-y-2.5">
        {rows.map((r) => (
          <div key={r.key} className="flex items-center gap-3">
            <span className="w-20 text-sm">{r.label}</span>
            <span className="h-2 flex-1 overflow-hidden rounded-full bg-muted">
              <span
                className="block h-full rounded-full bg-primary/70"
                style={{ width: `${(r.n / total) * 100}%` }}
              />
            </span>
            <span className="tnum w-8 text-right text-sm text-muted-foreground">{r.n}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
