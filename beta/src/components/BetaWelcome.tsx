import { useEffect, useLayoutEffect, useRef, useState } from "react";

/* "Welcome to the beta test", the way the Test tab says a pilot's name after the
 * activation code: one letter at a time, each rising out of its own line and resolving
 * out of a blur, painted with the same warm ramp running left to right across each line.
 * The timings, easing and five stops are the Test tab's own (.name .ch in its
 * index.html), so the two read as one product.
 *
 * Shown every time beta mode is entered: the app makes a fresh page each time, and this
 * plays once per page. A tap skips it. */

const LINES = ["Welcome to", "the beta test"];

const STAGGER_MS = 78; // between letters
const SETTLE_MS = 1150; // one letter's rise
const HOLD_MS = 700; // the whole line sitting still before it hands the screen over
const LEAVE_MS = 700;

type Phase = "pre" | "in" | "out" | "gone";

export function BetaWelcome() {
  const [phase, setPhase] = useState<Phase>("pre");
  const word = useRef<HTMLDivElement>(null);
  const letters = LINES.reduce((n, l) => n + l.replace(/ /g, "").length, 0);
  const reduced =
    typeof window !== "undefined" && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // Sized to the window, like fitName: measured at 100px and scaled so the longer line
  // spans most of the width, capped by the height on a short screen. Then the ramp,
  // like paintRamp: each letter gets the gradient at its line's width, slid left by its
  // own distance from the line's first letter, so the line reads as one fade.
  useLayoutEffect(() => {
    const el = word.current;
    if (!el) return;
    el.style.fontSize = "100px";
    const widest = Math.max(
      ...[...el.querySelectorAll<HTMLElement>(".bw-line")].map((l) => l.scrollWidth),
    );
    const size = Math.min((window.innerWidth * 0.86 * 100) / widest, window.innerHeight * 0.11);
    el.style.fontSize = `${Math.floor(size)}px`;
    el.querySelectorAll<HTMLElement>(".bw-line").forEach((line) => {
      const ch = [...line.querySelectorAll<HTMLElement>(".bw-ch")];
      if (!ch.length) return;
      const x0 = Math.min(...ch.map((c) => c.offsetLeft));
      const w = Math.max(...ch.map((c) => c.offsetLeft + c.offsetWidth)) - x0;
      ch.forEach((c) => {
        c.style.setProperty("--ramp-w", `${w}px`);
        c.style.setProperty("--ramp-x", `${x0 - c.offsetLeft}px`);
      });
    });
  }, []);

  useEffect(() => {
    // Two frames, so the letters are painted in their starting place before they move.
    let raf = requestAnimationFrame(() => {
      raf = requestAnimationFrame(() => setPhase("in"));
    });
    const arrive = reduced ? 600 : (letters - 1) * STAGGER_MS + SETTLE_MS;
    const out = window.setTimeout(() => setPhase("out"), arrive + HOLD_MS);
    const gone = window.setTimeout(() => setPhase("gone"), arrive + HOLD_MS + LEAVE_MS);
    return () => {
      cancelAnimationFrame(raf);
      clearTimeout(out);
      clearTimeout(gone);
    };
  }, [letters, reduced]);

  const skip = () => {
    if (phase === "out" || phase === "gone") return;
    setPhase("out");
    window.setTimeout(() => setPhase("gone"), LEAVE_MS);
  };

  if (phase === "gone") return null;

  let i = 0;
  return (
    <div
      role="status"
      aria-label={LINES.join(" ")}
      onClick={skip}
      className={`bw ${phase === "out" ? "bw-out" : ""} ${reduced ? "bw-reduced" : ""}`}
    >
      <div ref={word} className="bw-word" aria-hidden>
        {LINES.map((line) => (
          <span key={line} className="bw-line">
            {[...line].map((c, k) => {
              if (c === " ") return <span key={k} className="bw-sp" />;
              const delay = i++ * STAGGER_MS;
              return (
                <span
                  key={k}
                  className={`bw-ch ${phase !== "pre" ? "in" : ""}`}
                  style={{ transitionDelay: reduced ? "0ms" : `${delay}ms` }}
                >
                  {c}
                </span>
              );
            })}
          </span>
        ))}
      </div>
      <p className={`bw-note ${phase !== "pre" ? "in" : ""}`} aria-hidden>
        The next IMPKT app, on your wraps
      </p>
    </div>
  );
}
