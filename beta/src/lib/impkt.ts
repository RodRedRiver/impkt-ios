export type PunchType = "jab" | "cross" | "hook" | "uppercut";

export type Punch = {
  t: number; // ms since session start
  peakG: number; // internal only — never surfaced to the athlete
  velocity: number; // m/s
  /** Demo punches only. The band does not classify punches, so a real one has no type. */
  type?: PunchType | undefined;
  /** Real punches: which wrap threw it, when the wrap has said. */
  hand?: "L" | "R" | undefined;
  /** Real punches: the firmware's own power score, which `power` returns as it is. */
  score?: number | undefined;
};

export type Session = {
  id: string;
  startedAt: number;
  endedAt: number;
  punches: Punch[];
  title?: string | undefined;
};

export type Profile = {
  name: string;
  weightKg: number;
  heightCm: number;
  reachCm: number;
  stance: "orthodox" | "southpaw";
};

export type TextScale = "default" | "large" | "xl";
export type MotionPref = "system" | "reduced";

export type PairedDevice = {
  id: string;
  name: string;
  pairedAt: number;
};

export type Goals = {
  punches: number; // target punches per session
  tempo: number; // target punches per minute
};

export type Settings = {
  theme: "light" | "dark";
  bandName: string;
  gloveWeightKg: number;
  pairedDevices: PairedDevice[];
  textScale: TextScale;
  motion: MotionPref;
  profile: Profile;
  workout: string;
  goals: Goals;
};

export const WORKOUTS = ["Heavy Bag", "Speed Bag", "Pad Work", "Shadow Boxing", "Sparring"] as const;

export const defaultSettings: Settings = {
  theme: "dark",
  bandName: "BOXING-01",
  gloveWeightKg: 0.34,
  pairedDevices: [],
  textScale: "default",
  motion: "system",
  profile: { name: "", weightKg: 75, heightCm: 178, reachCm: 180, stance: "orthodox" },
  workout: "Heavy Bag",
  goals: { punches: 200, tempo: 30 },
};


/* ---------- metrics ---------- */

export const power = (p: Punch) => p.score ?? 4.0 * p.peakG + 6.0 * p.velocity;

export const TYPE_LABEL: Record<PunchType, string> = {
  jab: "Jab",
  cross: "Cross",
  hook: "Hook",
  uppercut: "Uppercut",
};

/** What to call one punch: its type for a demo punch, its hand for a real one. */
export const punchLabel = (p: Punch) =>
  p.type ? TYPE_LABEL[p.type] : p.hand === "L" ? "Left" : p.hand === "R" ? "Right" : "Punch";

const avg = (a: number[]) => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : 0);

export type SessionStats = {
  punches: number;
  durationMs: number;
  avgPower: number;
  bestPower: number;
  output: number; // total work
  tempo: number; // punches per minute
  fatigue: number; // % drop, last quarter vs first quarter
  fatigueReady: boolean;
  accuracy: number; // provisional consistency measure
  byType: Record<PunchType, number>;
  byHand: { L: number; R: number };
  /** True when any punch carries a type, which only demo punches do. */
  typed: boolean;
};

export function computeStats(punches: Punch[], durationMs: number): SessionStats {
  const scores = punches.map(power);
  const q = Math.max(1, Math.floor(punches.length / 4));
  const first = avg(scores.slice(0, q));
  const last = avg(scores.slice(-q));
  const fatigueReady = punches.length >= 8 && first > 0;
  const mean = avg(scores);
  const sd = scores.length
    ? Math.sqrt(avg(scores.map((s) => (s - mean) ** 2)))
    : 0;
  const byType: Record<PunchType, number> = { jab: 0, cross: 0, hook: 0, uppercut: 0 };
  const byHand = { L: 0, R: 0 };
  for (const p of punches) {
    if (p.type) byType[p.type] += 1;
    if (p.hand) byHand[p.hand] += 1;
  }

  return {
    punches: punches.length,
    durationMs,
    avgPower: mean,
    bestPower: scores.length ? Math.max(...scores) : 0,
    output: Math.round(scores.reduce((a, b) => a + b, 0) / 10),
    tempo: durationMs > 0 ? punches.length / (durationMs / 60000) : 0,
    fatigue: fatigueReady ? Math.max(0, ((first - last) / first) * 100) : 0,
    fatigueReady,
    accuracy: scores.length ? Math.max(0, Math.min(100, 100 - (sd / (mean || 1)) * 100)) : 0,
    byType,
    byHand,
    typed: punches.some((p) => p.type),
  };
}

/** Rolling power curve over the session, smoothed into `buckets` points. */
export function powerCurve(punches: Punch[], buckets = 24): number[] {
  if (punches.length === 0) return [];
  const size = Math.max(1, Math.ceil(punches.length / buckets));
  const out: number[] = [];
  for (let i = 0; i < punches.length; i += size) {
    out.push(avg(punches.slice(i, i + size).map(power)));
  }
  return out;
}

/* ---------- storage ---------- */

const SESSIONS_KEY = "impkt.sessions.v2";
const SETTINGS_KEY = "impkt.settings.v2";

export function loadSessions(): Session[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = window.localStorage.getItem(SESSIONS_KEY);
    return raw ? (JSON.parse(raw) as Session[]) : [];
  } catch {
    return [];
  }
}

export function writeSessions(list: Session[]) {
  if (typeof window === "undefined") return;
  window.localStorage.setItem(SESSIONS_KEY, JSON.stringify(list));
}

export function saveSession(session: Session) {
  writeSessions([session, ...loadSessions().filter((s) => s.id !== session.id)]);
}

export function deleteSession(id: string) {
  writeSessions(loadSessions().filter((s) => s.id !== id));
}

/** Rename a saved session. An empty name restores the default date title. */
export function renameSession(id: string, title: string): Session[] {
  const next = loadSessions().map((s) =>
    s.id === id ? { ...s, title: title.trim() || undefined } : s,
  );
  writeSessions(next);
  return next;
}

export const sessionTitle = (s: Session) => s.title?.trim() || fmtDay(s.startedAt);

export function clearSessions() {
  writeSessions([]);
}

export function loadSettings(): Settings {
  if (typeof window === "undefined") return defaultSettings;
  try {
    const raw = window.localStorage.getItem(SETTINGS_KEY);
    if (!raw) return defaultSettings;
    const parsed = JSON.parse(raw) as Partial<Settings>;
    return {
      ...defaultSettings,
      ...parsed,
      profile: { ...defaultSettings.profile, ...(parsed.profile ?? {}) },
      goals: { ...defaultSettings.goals, ...(parsed.goals ?? {}) },
    };
  } catch {
    return defaultSettings;
  }
}

export function storeSettings(s: Settings) {
  if (typeof window === "undefined") return;
  window.localStorage.setItem(SETTINGS_KEY, JSON.stringify(s));
}

/* ---------- demo punch source ---------- */

const TYPES: PunchType[] = ["jab", "cross", "hook", "uppercut"];

export function demoPunch(t: number, elapsedFraction = 0): Punch {
  const fade = 1 - Math.min(0.25, elapsedFraction * 0.25); // gentle fatigue over time
  const peakG = (7 + Math.random() * 7) * fade;
  const velocity = (4 + Math.random() * 4) * fade;
  return {
    t,
    peakG: Number(peakG.toFixed(2)),
    velocity: Number(velocity.toFixed(2)),
    type: TYPES[Math.floor(Math.random() * TYPES.length)]!,
  };
}

/* ---------- formatting ---------- */

export const fmt = (n: number, d = 0) =>
  n.toLocaleString("en-GB", { minimumFractionDigits: d, maximumFractionDigits: d });

export function fmtDuration(ms: number) {
  const total = Math.max(0, Math.round(ms / 1000));
  const m = Math.floor(total / 60);
  const s = total % 60;
  return `${m}:${String(s).padStart(2, "0")}`;
}

export function fmtDay(ts: number) {
  return new Date(ts).toLocaleDateString("en-GB", {
    weekday: "long",
    day: "numeric",
    month: "short",
  });
}

export function fmtTime(ts: number) {
  return new Date(ts).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });
}

export function groupSessions(sessions: Session[]) {
  const now = new Date();
  const weekAgo = now.getTime() - 7 * 86400000;
  const groups: { label: string; items: Session[] }[] = [];
  const week = sessions.filter((s) => s.startedAt >= weekAgo);
  if (week.length) groups.push({ label: "This week", items: week });
  const rest = sessions.filter((s) => s.startedAt < weekAgo);
  const byMonth = new Map<string, Session[]>();
  for (const s of rest) {
    const key = new Date(s.startedAt).toLocaleDateString("en-GB", {
      month: "long",
      year: "numeric",
    });
    byMonth.set(key, [...(byMonth.get(key) ?? []), s]);
  }
  for (const [label, items] of byMonth) groups.push({ label, items });
  return groups;
}

/* ---------- interpretation ---------- */

/** One short, honest sentence about the session. */
export function insight(st: SessionStats, priorFatigues: number[] = []): string {
  if (st.punches < 8) {
    return "Short session — record at least eight punches for a reliable fatigue read.";
  }
  const drop = st.fatigue;
  const baseline = priorFatigues.length
    ? priorFatigues.reduce((a, b) => a + b, 0) / priorFatigues.length
    : null;
  const shape =
    baseline === null
      ? "This is your first reference point."
      : drop > baseline + 4
        ? "Steeper than your recent average."
        : drop < baseline - 4
          ? "Flatter than your recent average — you held output well."
          : "In line with your recent average.";

  if (drop < 5) {
    return `Output held almost flat across the session (${fmt(drop, 1)}% drop). ${shape}`;
  }
  return `Your output dropped ${fmt(drop, 1)}% from the first quarter to the last. ${shape}`;
}
