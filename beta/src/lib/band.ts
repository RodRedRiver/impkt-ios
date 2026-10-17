/* ---------- the real band ----------
 *
 * Punches off the BOXING-01 wraps, from one of two places.
 *
 * Inside the IMPKT iOS app (the Beta tab) the app hands them over. A wrap accepts one
 * Bluetooth connection and the app's Test tab already holds it, so this page never
 * opens a link of its own: it asks the app to connect, and the app passes on every
 * punch it reads off that link. The messages are `impktBeta` down to the app and
 * `window.__impktBeta` back up, and BetaPage.swift is the other end.
 *
 * In a browser with Web Bluetooth (Chrome on desktop or Android) this page connects to
 * one wrap itself and reads the same twenty byte punch record the app does.
 *
 * Anywhere else there is no band, and the record screen falls back to demo punches.
 */

import { useSyncExternalStore } from "react";

/** Built for the iOS app's Beta tab (`npm run build:app`) rather than for the web. */
export const IN_APP = import.meta.env["VITE_IN_APP"] === "1";

export type Hand = "L" | "R";

export type BandPunch = {
  /** The firmware's power score, the same number the app's other tabs show. */
  power: number;
  /** Peak linear acceleration in g, rebuilt by the firmware when it went off the scale. */
  peakG: number;
  /** Peak hand speed, m/s. */
  speed: number;
  hand?: Hand | undefined;
};

export type BandWrap = {
  hand?: Hand | undefined;
  name: string;
  battery?: string | undefined;
  fw?: string | undefined;
};

export type BandState = {
  /** Where punches come from: the iOS app, this browser's Bluetooth, or nowhere. */
  source: "app" | "web" | "none";
  status: "disconnected" | "connecting" | "connected";
  wraps: BandWrap[];
  /** App only. The Test tab's activation code is the front door to the Bluetooth link. */
  activated: boolean;
  bluetoothOn: boolean;
  /** App only. A drill is running on the Test tab, and the app will not reconnect under it. */
  drillRunning: boolean;
  /** The last thing worth telling the boxer about a connect, or null. */
  message: string | null;
};

type AppState = {
  poweredOn: boolean;
  activated: boolean;
  running: boolean;
  wraps: { hand?: string; name: string; battery?: string; fw?: string }[];
};

type Bridge = {
  state: (s: AppState) => void;
  punch: (p: BandPunch) => void;
  reply: (id: number, ok: boolean, payload: Record<string, unknown>) => void;
};

declare global {
  interface Window {
    __impktBeta?: Bridge;
    webkit?: {
      messageHandlers?: Record<string, { postMessage: (m: unknown) => void } | undefined>;
    };
  }
}

const PUNCH_SERVICE = "6e2a0001-b5a3-f393-e0a9-e50e24dcca9e";
const PUNCH_DATA = "6e2a0002-b5a3-f393-e0a9-e50e24dcca9e";
const PUNCH_SCORE = "6e2a0003-b5a3-f393-e0a9-e50e24dcca9e";
const PUNCH_IDENT = "6e2a0009-b5a3-f393-e0a9-e50e24dcca9e";

const appHandler = () =>
  typeof window === "undefined" ? undefined : window.webkit?.messageHandlers?.["impktBeta"];

type WebBluetooth = {
  requestDevice: (o: unknown) => Promise<WebDevice>;
};
type WebDevice = EventTarget & {
  name?: string;
  gatt?: { connect: () => Promise<WebServer>; disconnect: () => void; connected: boolean };
};
type WebServer = {
  getPrimaryService: (uuid: string) => Promise<{
    getCharacteristic: (uuid: string) => Promise<WebChar>;
  }>;
};
type WebChar = EventTarget & {
  value?: DataView;
  readValue: () => Promise<DataView>;
  startNotifications: () => Promise<WebChar>;
};

const webBluetooth = (): WebBluetooth | undefined =>
  typeof navigator === "undefined"
    ? undefined
    : (navigator as Navigator & { bluetooth?: WebBluetooth }).bluetooth;

function initialSource(): BandState["source"] {
  if (appHandler()) return "app";
  if (webBluetooth()) return "web";
  return "none";
}

let state: BandState = {
  source: "none",
  status: "disconnected",
  wraps: [],
  activated: false,
  bluetoothOn: true,
  drillRunning: false,
  message: null,
};
let started = false;
const stateListeners = new Set<() => void>();
const punchListeners = new Set<(p: BandPunch) => void>();

function set(patch: Partial<BandState>) {
  state = { ...state, ...patch };
  stateListeners.forEach((fn) => fn());
}

function deliver(p: BandPunch) {
  punchListeners.forEach((fn) => {
    try {
      fn(p);
    } catch (e) {
      console.error(e);
    }
  });
}

/* ---------- the app ---------- */

let seq = 1;
const pending = new Map<number, (ok: boolean, payload: Record<string, unknown>) => void>();

function ask(op: string, args: Record<string, unknown> = {}, timeoutMs = 15000) {
  return new Promise<Record<string, unknown>>((resolve, reject) => {
    const handler = appHandler();
    if (!handler) return reject(new Error("not in the app"));
    const id = seq++;
    const timer = setTimeout(() => {
      pending.delete(id);
      reject(new Error("the app did not answer"));
    }, timeoutMs);
    pending.set(id, (ok, payload) => {
      clearTimeout(timer);
      if (ok) resolve(payload);
      else reject(new Error(String(payload["why"] ?? "refused")));
    });
    handler.postMessage({ id, op, args });
  });
}

function startApp() {
  window.__impktBeta = {
    state: (s) => {
      const wraps = s.wraps.map((w) => ({
        name: w.name,
        battery: w.battery || undefined,
        fw: w.fw || undefined,
        hand: w.hand === "L" || w.hand === "R" ? (w.hand as Hand) : undefined,
      }));
      set({
        bluetoothOn: s.poweredOn,
        activated: s.activated,
        drillRunning: s.running,
        wraps,
        // A connect in flight keeps saying so until it answers, rather than flicking
        // to "disconnected" on the poll that lands while the app is still searching.
        status: wraps.length
          ? "connected"
          : state.status === "connecting"
            ? "connecting"
            : "disconnected",
      });
    },
    punch: (p) => deliver(p),
    reply: (id, ok, payload) => {
      const done = pending.get(id);
      if (!done) return;
      pending.delete(id);
      done(ok, payload ?? {});
    },
  };
  // The app pushes state on a timer, and this asks for it now so the first paint is right.
  ask("hello").catch(() => {});
}

/** The app's answer to a failed connect, in a sentence a boxer can act on. */
function appReason(why: string): string {
  switch (why) {
    case "no bluetooth":
      return "Bluetooth is off for IMPKT. Turn it on in Settings.";
    case "none found":
      return "No wrap answered. Shake it to wake it, keep it close, and try again.";
    case "a drill is running":
      return "A drill is running on the Test tab. Finish it there first.";
    case "not activated":
      return "Enter your activation code on the Test tab first.";
    case "no page":
    case "the page did not answer":
      return "Open the Test tab once so the app can reach the wraps, then try again.";
    default:
      return `That did not connect (${why}).`;
  }
}

/* ---------- a browser with Web Bluetooth ---------- */

let webDevice: WebDevice | null = null;

/** The twenty byte punch record, as Punch.swift in the app reads it. */
export function parsePunchRecord(v: DataView): BandPunch | null {
  if (v.byteLength < 20) return null;
  const u16 = (at: number) => v.getUint16(at, true);
  const flags = v.getUint8(16);
  if (flags & 0x04) return null; // thrown while the link was down, arriving late
  const score = u16(2) / 10;
  const peakG = u16(4) / 1000;
  const rawG = u16(6) / 1000;
  const speed = u16(8) / 1000;
  const rebuilt = (flags & 0x08) !== 0;
  const builtPeak = u16(18) / 1000;
  const peak = rebuilt && builtPeak > 0 ? builtPeak : Math.max(peakG, rawG - 1);
  // The board's own score. Firmware older than v2.21 scored a punch that went off the
  // scale from the rail; the app rebuilds that case in Punch.swift, a browser does not.
  return { power: Math.round(score), peakG: peak, speed };
}

function parseBareScore(v: DataView): BandPunch | null {
  if (v.byteLength < 4) return null;
  const score = v.getFloat32(0, true);
  if (!Number.isFinite(score) || score <= 0) return null;
  return { power: Math.round(score), peakG: score / 4, speed: 0 };
}

async function connectWeb() {
  const bt = webBluetooth();
  if (!bt) return;
  set({ status: "connecting", message: null });
  try {
    const device = await bt.requestDevice({
      filters: [{ services: [PUNCH_SERVICE] }],
      optionalServices: [PUNCH_SERVICE],
    });
    const server = await device.gatt!.connect();
    const service = await server.getPrimaryService(PUNCH_SERVICE);

    let hand: Hand | undefined;
    try {
      const ident = await (await service.getCharacteristic(PUNCH_IDENT)).readValue();
      const h = ident.byteLength >= 2 ? String.fromCharCode(ident.getUint8(1)) : "";
      if (h === "L" || h === "R") hand = h;
    } catch {
      // A board too old to say which hand it is on. Its punches count with no hand.
    }

    let ch: WebChar;
    let parse: (v: DataView) => BandPunch | null;
    try {
      ch = await service.getCharacteristic(PUNCH_DATA);
      parse = parsePunchRecord;
    } catch {
      ch = await service.getCharacteristic(PUNCH_SCORE);
      parse = parseBareScore;
    }
    ch.addEventListener("characteristicvaluechanged", () => {
      const p = ch.value ? parse(ch.value) : null;
      if (p) deliver({ ...p, hand });
    });
    await ch.startNotifications();

    device.addEventListener("gattserverdisconnected", () => {
      if (webDevice !== device) return;
      webDevice = null;
      set({ status: "disconnected", wraps: [], message: "The wrap disconnected." });
    });
    webDevice = device;
    set({ status: "connected", wraps: [{ name: device.name || "BOXING-01", hand }] });
  } catch (e) {
    const name = (e as Error).name;
    set({
      status: "disconnected",
      message:
        name === "NotFoundError" ? null : "That wrap did not connect. Shake it and try again.",
    });
  }
}

/* ---------- what the screens use ---------- */

function start() {
  if (started || typeof window === "undefined") return;
  started = true;
  const source = initialSource();
  set({ source });
  if (source === "app") startApp();
}

export function getBand(): BandState {
  start();
  return state;
}

export function useBand(): BandState {
  return useSyncExternalStore(
    (fn) => {
      start();
      stateListeners.add(fn);
      return () => stateListeners.delete(fn);
    },
    () => state,
    () => state,
  );
}

/** Every punch the band reports from now on. Returns the unsubscribe. */
export function onPunch(fn: (p: BandPunch) => void): () => void {
  start();
  punchListeners.add(fn);
  return () => punchListeners.delete(fn);
}

export async function connectBand(): Promise<void> {
  start();
  if (state.source === "web") return connectWeb();
  if (state.source !== "app") return;
  set({ status: "connecting", message: null });
  try {
    await ask("connect", {}, 20000);
    set({ status: state.wraps.length ? "connected" : "disconnected", message: null });
  } catch (e) {
    set({
      status: state.wraps.length ? "connected" : "disconnected",
      message: appReason((e as Error).message),
    });
  }
}

export async function disconnectBand(): Promise<void> {
  start();
  if (state.source === "web") {
    const d = webDevice;
    webDevice = null;
    d?.gatt?.disconnect();
    set({ status: "disconnected", wraps: [], message: null });
    return;
  }
  if (state.source === "app") {
    await ask("disconnect").catch(() => {});
  }
}

/** Shows one of the app's own tabs: "test", "devices" and so on. No-op in a browser. */
export function openAppTab(tab: string) {
  appHandler()?.postMessage({ op: "openTab", args: { tab } });
}

export function bandLabel(s: BandState): string {
  if (s.status === "connecting") return "Connecting to your wraps…";
  if (s.status !== "connected") return "Tap to connect your wraps";
  const hands = s.wraps.map((w) => (w.hand === "L" ? "Left" : w.hand === "R" ? "Right" : w.name));
  return `Connected · ${hands.join(" + ")}`;
}
