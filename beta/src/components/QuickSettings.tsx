import { Link } from "@tanstack/react-router";
import { Bluetooth, Trash2, X } from "lucide-react";
import { useSettings } from "@/lib/settings";

type Props = {
  open: boolean;
  onClose: () => void;
  onRepair: (id: string) => void;
  activeDeviceId?: string | null;
};

function Field({
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
    <label className="flex items-center justify-between gap-4 rounded-2xl border border-white/60 bg-white/45 px-4 py-3 backdrop-blur-xl">
      <span className="text-[13px] font-medium text-[#3A3A3C]">{label}</span>
      <span className="flex items-center gap-1.5">
        <input
          type="number"
          inputMode="decimal"
          step={step}
          min={min}
          max={max}
          value={value}
          onChange={(e) => {
            const n = Number(e.target.value);
            if (!Number.isNaN(n)) onChange(Math.min(max, Math.max(min, n)));
          }}
          className="w-20 rounded-lg border border-black/5 bg-white/80 px-2 py-1 text-right text-[15px] font-semibold tabular-nums text-[#1C1C1E] outline-none focus:ring-2 focus:ring-[#A00D2D]/30"
        />
        <span className="text-[12px] text-[#8E8E93]">{unit}</span>
      </span>
    </label>
  );
}

export function QuickSettings({ open, onClose, onRepair, activeDeviceId }: Props) {
  const { settings, update } = useSettings();
  if (!open) return null;

  const devices = settings.pairedDevices;

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center sm:items-center">
      <button
        aria-label="Close settings"
        onClick={onClose}
        className="absolute inset-0 bg-black/25 backdrop-blur-[2px]"
      />
      <div
        role="dialog"
        aria-modal="true"
        aria-label="Settings"
        className="relative m-3 w-full max-w-[380px] rounded-[28px] border border-white/60 bg-[#FBFAF8]/85 p-5 shadow-[0_30px_80px_-20px_rgba(0,0,0,0.35)] backdrop-blur-[30px] saturate-[180%]"
      >
        <div className="flex items-center justify-between">
          <h2 className="text-[19px] font-semibold tracking-[-0.02em] text-[#1C1C1E]">Settings</h2>
          <button
            onClick={onClose}
            aria-label="Close"
            className="flex h-8 w-8 items-center justify-center rounded-full text-[#8E8E93] transition-transform active:scale-90"
          >
            <X className="h-[18px] w-[18px]" strokeWidth={1.8} />
          </button>
        </div>

        <p className="mt-1 text-[12px] text-[#8E8E93]">
          Body mass and glove weight are used for force estimation.
        </p>

        <div className="mt-4 space-y-2">
          <Field
            label="Body mass"
            value={settings.profile.weightKg}
            unit="kg"
            step={0.5}
            min={25}
            max={200}
            onChange={(v) => update({ profile: { ...settings.profile, weightKg: v } })}
          />
          <Field
            label="Glove weight"
            value={settings.gloveWeightKg}
            unit="kg"
            step={0.01}
            min={0}
            max={1.5}
            onChange={(v) => update({ gloveWeightKg: v })}
          />
        </div>

        <h3 className="mt-6 text-[13px] font-semibold text-[#1C1C1E]">Devices</h3>
        <div className="mt-2 space-y-2">
          {devices.length === 0 && (
            <p className="rounded-2xl border border-white/60 bg-white/40 px-4 py-3 text-[12px] text-[#8E8E93]">
              No paired devices yet. Tap the pairing pill to connect your BOXING-01.
            </p>
          )}
          {devices.map((d) => {
            const active = d.id === activeDeviceId;
            return (
              <div
                key={d.id}
                className="flex items-center justify-between gap-3 rounded-2xl border border-white/60 bg-white/45 px-4 py-3 backdrop-blur-xl"
              >
                <span className="min-w-0">
                  <span className="flex items-center gap-1.5 text-[13px] font-medium text-[#1C1C1E]">
                    <Bluetooth className="h-3.5 w-3.5 text-[#3A3A3C]" strokeWidth={2} />
                    {d.name}
                  </span>
                  <span className="mt-0.5 block text-[11px] text-[#8E8E93]">
                    {active ? "Connected" : "Not connected"} · paired{" "}
                    {new Date(d.pairedAt).toLocaleDateString()}
                  </span>
                </span>
                <span className="flex shrink-0 items-center gap-2">
                  <button
                    onClick={() => onRepair(d.id)}
                    className="rounded-full bg-[#A00D2D] px-3 py-1.5 text-[12px] font-semibold text-white transition-transform active:scale-95"
                  >
                    {active ? "Disconnect" : "Re-pair"}
                  </button>
                  <button
                    aria-label={`Forget ${d.name}`}
                    onClick={() =>
                      update({ pairedDevices: devices.filter((x) => x.id !== d.id) })
                    }
                    className="flex h-8 w-8 items-center justify-center rounded-full text-[#8E8E93] transition-transform active:scale-90"
                  >
                    <Trash2 className="h-4 w-4" strokeWidth={1.7} />
                  </button>
                </span>
              </div>
            );
          })}
        </div>

        <Link
          to="/settings"
          onClick={onClose}
          className="mt-5 block rounded-2xl border border-white/60 bg-white/40 px-4 py-3 text-center text-[13px] font-medium text-[#3A3A3C]"
        >
          All settings
        </Link>
      </div>
    </div>
  );
}
