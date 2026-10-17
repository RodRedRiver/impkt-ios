import { computeStats, loadSessions, power, type Session, type Settings } from "@/lib/impkt";

export type AlertKind = "milestone" | "reminder" | "info";

export type Alert = {
  id: string;
  kind: AlertKind;
  title: string;
  body: string;
  createdAt: number; // when it becomes visible
  read: boolean;
};

const KEY = "impkt.alerts.v1";
const DAY = 86400000;

export function loadAlerts(): Alert[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = window.localStorage.getItem(KEY);
    const list = raw ? (JSON.parse(raw) as Alert[]) : [];
    return list.sort((a, b) => b.createdAt - a.createdAt);
  } catch {
    return [];
  }
}

function write(list: Alert[]): Alert[] {
  const sorted = [...list].sort((a, b) => b.createdAt - a.createdAt).slice(0, 60);
  if (typeof window !== "undefined") window.localStorage.setItem(KEY, JSON.stringify(sorted));
  return sorted;
}

/** Alerts that are due now (scheduled reminders stay hidden until their time). */
export const visibleAlerts = (list: Alert[], now = Date.now()) =>
  list.filter((a) => a.createdAt <= now);

export const unreadCount = (list: Alert[], now = Date.now()) =>
  visibleAlerts(list, now).filter((a) => !a.read).length;

/** Adds alerts, skipping any id that already exists. Returns the full stored list. */
export function pushAlerts(incoming: Alert[]): Alert[] {
  const current = loadAlerts();
  const seen = new Set(current.map((a) => a.id));
  const fresh = incoming.filter((a) => !seen.has(a.id));
  if (fresh.length === 0) return current;
  return write([...current, ...fresh]);
}

export function markAllRead(): Alert[] {
  return write(loadAlerts().map((a) => (a.createdAt <= Date.now() ? { ...a, read: true } : a)));
}

export function markRead(id: string): Alert[] {
  return write(loadAlerts().map((a) => (a.id === id ? { ...a, read: true } : a)));
}

export function dismissAlert(id: string): Alert[] {
  return write(loadAlerts().filter((a) => a.id !== id));
}

export function clearAlerts(): Alert[] {
  return write([]);
}

const alert = (
  id: string,
  kind: AlertKind,
  title: string,
  body: string,
  createdAt: number,
): Alert => ({ id, kind, title, body, createdAt, read: false });

/**
 * Milestone + post-workout alerts for a session that just finished.
 * Scheduled reminders carry a future `createdAt` and surface when due.
 */
export function alertsForSession(session: Session, settings: Settings): Alert[] {
  const stats = computeStats(session.punches, session.endedAt - session.startedAt);
  const out: Alert[] = [];
  const at = session.endedAt;
  const sid = session.id;

  if (stats.punches >= settings.goals.punches) {
    out.push(
      alert(
        `${sid}:goal-punches`,
        "milestone",
        "Punch goal reached",
        `${stats.punches} punches against a target of ${settings.goals.punches}.`,
        at,
      ),
    );
  }
  if (stats.tempo >= settings.goals.tempo) {
    out.push(
      alert(
        `${sid}:goal-tempo`,
        "milestone",
        "Tempo goal reached",
        `You held ${Math.round(stats.tempo)} punches per minute (target ${settings.goals.tempo}).`,
        at,
      ),
    );
  }

  const priorBest = loadSessions()
    .filter((s) => s.id !== sid)
    .flatMap((s) => s.punches.map(power))
    .reduce((a, b) => Math.max(a, b), 0);
  if (priorBest > 0 && stats.bestPower > priorBest) {
    out.push(
      alert(
        `${sid}:pb-power`,
        "milestone",
        "New personal best",
        `Your hardest punch yet — ${Math.round(stats.bestPower)} beats ${Math.round(priorBest)}.`,
        at,
      ),
    );
  }

  if (stats.fatigueReady && stats.fatigue < 5) {
    out.push(
      alert(
        `${sid}:flat-output`,
        "milestone",
        "Output held flat",
        `Only a ${stats.fatigue.toFixed(1)}% drop from your first quarter to your last.`,
        at,
      ),
    );
  }

  out.push(
    alert(
      `${sid}:cooldown`,
      "reminder",
      "Cool down and hydrate",
      "Five minutes of light shadow boxing and stretching helps recovery.",
      at + 60000,
    ),
  );
  out.push(
    alert(
      `${sid}:next-session`,
      "reminder",
      "Ready for the next round?",
      "It has been a day since your last session — a short bag round keeps momentum.",
      at + DAY,
    ),
  );

  return out;
}

/** Generic reminder when nothing has been recorded for a while. */
export function idleReminder(now = Date.now()): Alert[] {
  const last = loadSessions()[0];
  if (!last) {
    return [
      alert(
        "welcome",
        "info",
        "Welcome to IMPKT",
        "Record your first session and milestone alerts will appear here.",
        now,
      ),
    ];
  }
  if (now - last.endedAt < 3 * DAY) return [];
  const bucket = Math.floor((now - last.endedAt) / (3 * DAY));
  return [
    alert(
      `idle:${last.id}:${bucket}`,
      "reminder",
      "Three days without training",
      "Jump back in with a short open session to protect your tempo.",
      now,
    ),
  ];
}
