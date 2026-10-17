type Props = {
  values: number[];
  height?: number;
  label?: string;
};

/** Smooth area chart of average power across the session. */
export function PowerCurve({ values, height = 120, label }: Props) {
  if (values.length < 2) {
    return (
      <div
        className="flex items-center justify-center rounded-[20px] border border-dashed border-border text-xs text-muted-foreground"
        style={{ height }}
      >
        Not enough punches yet
      </div>
    );
  }

  const max = Math.max(...values) * 1.1 || 1;
  const min = Math.min(...values) * 0.85;
  const span = max - min || 1;
  const pts = values.map((v, i) => {
    const x = (i / (values.length - 1)) * 100;
    const y = 100 - ((v - min) / span) * 100;
    return `${x.toFixed(2)},${y.toFixed(2)}`;
  });

  return (
    <div>
      {label ? <div className="label-xs mb-2">{label}</div> : null}
      <svg viewBox="0 0 100 100" preserveAspectRatio="none" style={{ height }} className="w-full">
        <defs>
          <linearGradient id="pcFill" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="var(--primary)" stopOpacity="0.35" />
            <stop offset="100%" stopColor="var(--primary)" stopOpacity="0" />
          </linearGradient>
        </defs>
        <polygon points={`0,100 ${pts.join(" ")} 100,100`} fill="url(#pcFill)" />
        <polyline
          points={pts.join(" ")}
          fill="none"
          stroke="var(--primary)"
          strokeWidth="2"
          vectorEffect="non-scaling-stroke"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </svg>
    </div>
  );
}

/** Recent-punch intensity bars for the live view. */
export function IntensityBars({ values, height = 84 }: { values: number[]; height?: number }) {
  const max = Math.max(1, ...values);
  const shown = values.slice(-28);
  return (
    <div className="flex items-end gap-1" style={{ height }}>
      {shown.length === 0 ? (
        <div className="flex h-full w-full items-center justify-center text-xs text-muted-foreground">
          Waiting for punches
        </div>
      ) : (
        shown.map((v, i) => (
          <div
            key={i}
            className="flex-1 rounded-full bg-primary/80 transition-[height] duration-200"
            style={{ height: `${Math.max(6, (v / max) * 100)}%` }}
          />
        ))
      )}
    </div>
  );
}
