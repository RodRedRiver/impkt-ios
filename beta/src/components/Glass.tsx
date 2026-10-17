import type { ReactNode } from "react";
import { cn } from "@/lib/utils";

export function Panel({ className, children }: { className?: string; children: ReactNode }) {
  return <div className={cn("glass p-4", className)}>{children}</div>;
}

export function Metric({
  label,
  value,
  unit,
  hint,
  accent,
}: {
  label: string;
  value: ReactNode;
  unit?: string;
  hint?: string;
  accent?: boolean;
}) {
  return (
    <div className="glass px-4 py-3.5">
      <div className="label-xs">{label}</div>
      <div
        className={cn(
          "display tnum mt-1.5 text-[28px]",
          accent ? "text-primary" : "text-foreground",
        )}
      >
        {value}
        {unit ? <span className="ml-1 text-sm font-medium text-muted-foreground">{unit}</span> : null}
      </div>
      {hint ? <div className="mt-0.5 text-[11px] text-muted-foreground">{hint}</div> : null}
    </div>
  );
}

export function Provisional() {
  return (
    <span className="rounded-full bg-muted px-2 py-0.5 text-[10px] uppercase tracking-widest text-muted-foreground">
      Provisional
    </span>
  );
}
