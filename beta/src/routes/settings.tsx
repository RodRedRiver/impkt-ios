import { createFileRoute } from "@tanstack/react-router";
import { Moon, Sun } from "lucide-react";
import { useEffect, useState } from "react";
import { clearSessions } from "@/lib/impkt";
import { useSettings } from "@/lib/settings";

export const Route = createFileRoute("/settings")({
  head: () => ({
    meta: [
      { title: "Settings — IMPKT" },
      {
        name: "description",
        content: "Theme, band name, fighter profile and data controls for the IMPKT boxing app.",
      },
      { property: "og:title", content: "Settings — IMPKT" },
      { property: "og:description", content: "Theme, band name, fighter profile and data controls." },
    ],
  }),
  component: SettingsPage,
});

function SettingsPage() {
  const { settings, update } = useSettings();
  const { profile } = settings;
  const [cleared, setCleared] = useState(false);
  const [systemReduced, setSystemReduced] = useState(false);

  useEffect(() => {
    const mq = window.matchMedia("(prefers-reduced-motion: reduce)");
    const sync = () => setSystemReduced(mq.matches);
    sync();
    mq.addEventListener("change", sync);
    return () => mq.removeEventListener("change", sync);
  }, []);


  return (
    <div className="px-5 pt-14">
      <h1 className="display text-5xl">Settings</h1>

      <div className="glass mt-5 p-4">
        <div className="label-xs mb-3">Appearance</div>
        <div className="flex gap-2">
          {(["light", "dark"] as const).map((t) => (
            <button
              key={t}
              onClick={() => update({ theme: t })}
              className={`flex flex-1 items-center justify-center gap-2 rounded-full px-4 py-3 text-sm font-medium transition ${
                settings.theme === t
                  ? "bg-primary text-primary-foreground"
                  : "border border-border text-muted-foreground"
              }`}
            >
              {t === "light" ? <Sun className="h-4 w-4" /> : <Moon className="h-4 w-4" />}
              {t === "light" ? "Light" : "Dark"}
            </button>
          ))}
        </div>
      </div>

      <div className="glass mt-3 p-4">
        <div className="label-xs mb-3">Accessibility</div>

        <div className="mb-2 text-sm font-medium">Text size</div>
        <div className="flex gap-2" role="group" aria-label="Text size">
          {(
            [
              { id: "default", label: "Default" },
              { id: "large", label: "Large" },
              { id: "xl", label: "Extra large" },
            ] as const
          ).map((o) => (
            <button
              key={o.id}
              onClick={() => update({ textScale: o.id })}
              aria-pressed={settings.textScale === o.id}
              className={`min-h-11 flex-1 rounded-full px-3 py-2.5 text-sm font-medium transition ${
                settings.textScale === o.id
                  ? "bg-primary text-primary-foreground"
                  : "border border-border text-muted-foreground"
              }`}
            >
              {o.label}
            </button>
          ))}
        </div>

        <div className="mt-5 mb-2 text-sm font-medium">Motion</div>
        <div className="flex gap-2" role="group" aria-label="Motion preference">
          {(
            [
              { id: "system", label: "Match system" },
              { id: "reduced", label: "Reduce motion" },
            ] as const
          ).map((o) => (
            <button
              key={o.id}
              onClick={() => update({ motion: o.id })}
              aria-pressed={settings.motion === o.id}
              className={`min-h-11 flex-1 rounded-full px-3 py-2.5 text-sm font-medium transition ${
                settings.motion === o.id
                  ? "bg-primary text-primary-foreground"
                  : "border border-border text-muted-foreground"
              }`}
            >
              {o.label}
            </button>
          ))}
        </div>
        <p className="mt-2 text-xs text-muted-foreground">
          {settings.motion === "reduced"
            ? "Animations and transitions are switched off."
            : systemReduced
              ? "Your device asks for reduced motion, so animations are already off."
              : "Following your device setting for reduced motion."}
        </p>
      </div>

      <div className="glass mt-3 p-4">
        <div className="label-xs mb-3">Band</div>
        <Field
          label="Band name"
          value={settings.bandName}
          onChange={(v) => update({ bandName: v })}
        />
      </div>

      <div className="glass mt-3 space-y-3 p-4">
        <div className="label-xs">Fighter profile</div>
        <Field
          label="Name"
          value={profile.name}
          placeholder="Your name"
          onChange={(v) => update({ profile: { ...profile, name: v } })}
        />
        <div className="grid grid-cols-3 gap-2">
          <NumField
            label="Weight (kg)"
            value={profile.weightKg}
            onChange={(v) => update({ profile: { ...profile, weightKg: v } })}
          />
          <NumField
            label="Height (cm)"
            value={profile.heightCm}
            onChange={(v) => update({ profile: { ...profile, heightCm: v } })}
          />
          <NumField
            label="Reach (cm)"
            value={profile.reachCm}
            onChange={(v) => update({ profile: { ...profile, reachCm: v } })}
          />
        </div>
        <div>
          <div className="label-xs mb-2">Stance</div>
          <div className="flex gap-2">
            {(["orthodox", "southpaw"] as const).map((s) => (
              <button
                key={s}
                onClick={() => update({ profile: { ...profile, stance: s } })}
                className={`flex-1 rounded-full px-4 py-2.5 text-sm font-medium capitalize transition ${
                  profile.stance === s
                    ? "bg-primary text-primary-foreground"
                    : "border border-border text-muted-foreground"
                }`}
              >
                {s}
              </button>
            ))}
          </div>
        </div>
      </div>

      <div className="glass mt-3 p-4">
        <div className="label-xs mb-3">Data</div>
        <button
          onClick={() => {
            clearSessions();
            setCleared(true);
          }}
          className="w-full rounded-full border border-primary/40 py-3 text-sm font-medium text-primary"
        >
          Clear all sessions
        </button>
        {cleared ? (
          <p className="mt-2 text-center text-xs text-muted-foreground">All sessions removed.</p>
        ) : null}
      </div>

      <div className="glass mt-3 p-4 text-xs leading-relaxed text-muted-foreground">
        <div className="label-xs mb-2">Terms & Privacy</div>
        IMPKT stores your sessions and profile on this device only. Nothing is uploaded, sold or
        shared. Metrics are derived from wrist-sensor motion and are training indicators, not
        medical or competition measurements. Punch-type breakdown is provisional. Use the app at
        your own risk and train within your limits.
      </div>

      <p className="tnum mt-5 text-center text-xs text-muted-foreground">
        IMPKT 1.0.0 · BOXING-01 firmware 2.4
      </p>
    </div>

  );
}

function Field({
  label,
  value,
  onChange,
  placeholder,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
}) {
  return (
    <label className="block">
      <span className="label-xs">{label}</span>
      <input
        value={value}
        placeholder={placeholder}
        onChange={(e) => onChange(e.target.value)}
        className="mt-1 w-full rounded-[16px] border border-border bg-background/40 px-4 py-3 text-sm outline-none focus:border-primary"
      />
    </label>
  );
}

function NumField({
  label,
  value,
  onChange,
}: {
  label: string;
  value: number;
  onChange: (v: number) => void;
}) {
  return (
    <label className="block">
      <span className="label-xs">{label}</span>
      <input
        type="number"
        inputMode="numeric"
        value={value}
        onChange={(e) => onChange(Number(e.target.value))}
        className="tnum mt-1 w-full rounded-[16px] border border-border bg-background/40 px-3 py-3 text-sm outline-none focus:border-primary"
      />
    </label>
  );
}
