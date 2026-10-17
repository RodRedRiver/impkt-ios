import { useEffect, useRef } from "react";

const MAX_TILT = 15; // degrees
const SPRING = "transform 0.5s cubic-bezier(0.175, 0.885, 0.32, 1.275)";
const FOLLOW = "transform 0.1s ease-out";

type Props = {
  src: string;
  alt: string;
};

/**
 * Interactive 3D tilt wrapper for the band product render.
 * Pointer / touch-drag tilts up to ±15°, device orientation drives it on
 * mobile, a specular sheen tracks the tilt, and the ambient shadow shifts
 * opposite the tilt for depth. Resets with a gentle spring.
 */
export function TiltBand({ src, alt }: Props) {
  const wrapRef = useRef<HTMLDivElement>(null);
  const imgRef = useRef<HTMLImageElement>(null);
  const sheenRef = useRef<HTMLDivElement>(null);
  const shadowRef = useRef<HTMLDivElement>(null);
  // Current (damped) tilt in degrees; target tilt set by input sources.
  const cur = useRef({ x: 0, y: 0 });
  const target = useRef({ x: 0, y: 0 });
  const dragging = useRef(false);
  const gyroActive = useRef(false);
  const raf = useRef(0);

  useEffect(() => {
    const wrap = wrapRef.current;
    const img = imgRef.current;
    const sheen = sheenRef.current;
    const shadow = shadowRef.current;
    if (!wrap || !img || !sheen || !shadow) return;

    const reduceMotion =
      window.matchMedia("(prefers-reduced-motion: reduce)").matches ||
      document.documentElement.classList.contains("reduce-motion");
    if (reduceMotion) return;

    const render = () => {
      // Dampen toward the target for a smooth, weighted feel.
      const k = dragging.current || gyroActive.current ? 0.35 : 0.12;
      cur.current.x += (target.current.x - cur.current.x) * k;
      cur.current.y += (target.current.y - cur.current.y) * k;
      const { x, y } = cur.current; // x = rotateY, y = rotateX

      img.style.transform = `rotateX(${y.toFixed(2)}deg) rotateY(${x.toFixed(2)}deg)`;
      img.style.transition = dragging.current || gyroActive.current ? FOLLOW : SPRING;

      // Sheen: glare tracks the tilt, brightens as the angle grows.
      const mag = Math.min(1, Math.hypot(x, y) / MAX_TILT);
      sheen.style.opacity = (0.12 + mag * 0.5).toFixed(3);
      sheen.style.background = `radial-gradient(circle at ${50 + x * 3.2}% ${50 - y * 3.2}%, rgba(255,255,255,0.95) 0%, rgba(255,255,255,0.25) 32%, transparent 62%)`;

      // Ambient shadow shifts opposite the tilt.
      shadow.style.transform = `translate(${(-x * 1.6).toFixed(1)}px, ${(18 + y * 1.2).toFixed(1)}px) scale(${1 + mag * 0.04})`;
      shadow.style.opacity = (0.85 + mag * 0.15).toFixed(3);

      if (
        Math.abs(target.current.x - cur.current.x) > 0.01 ||
        Math.abs(target.current.y - cur.current.y) > 0.01 ||
        dragging.current ||
        gyroActive.current
      ) {
        raf.current = requestAnimationFrame(render);
      } else {
        raf.current = 0;
      }
    };

    const kick = () => {
      if (!raf.current) raf.current = requestAnimationFrame(render);
    };

    const setFromPoint = (clientX: number, clientY: number) => {
      const r = wrap.getBoundingClientRect();
      const px = (clientX - r.left) / r.width - 0.5; // -0.5..0.5
      const py = (clientY - r.top) / r.height - 0.5;
      target.current.x = Math.max(-MAX_TILT, Math.min(MAX_TILT, px * 2 * MAX_TILT));
      target.current.y = Math.max(-MAX_TILT, Math.min(MAX_TILT, -py * 2 * MAX_TILT));
      kick();
    };

    const onPointerMove = (e: PointerEvent) => {
      if (e.pointerType === "touch" && !dragging.current) return;
      dragging.current = e.pointerType === "touch" ? dragging.current : true;
      setFromPoint(e.clientX, e.clientY);
    };
    const onPointerDown = (e: PointerEvent) => {
      dragging.current = true;
      setFromPoint(e.clientX, e.clientY);
      // iOS 13+ requires a user gesture to enable orientation events.
      const doe = DeviceOrientationEvent as unknown as {
        requestPermission?: () => Promise<string>;
      };
      if (typeof doe.requestPermission === "function") {
        doe.requestPermission().catch(() => {});
      }
    };
    const onEnd = () => {
      dragging.current = false;
      if (!gyroActive.current) {
        target.current.x = 0;
        target.current.y = 0;
      }
      if (img) img.style.transition = SPRING;
      kick();
    };

    const onOrientation = (e: DeviceOrientationEvent) => {
      if (e.beta == null || e.gamma == null) return;
      gyroActive.current = true;
      // gamma: left/right tilt (-90..90), beta: front/back (-180..180).
      const gx = Math.max(-1, Math.min(1, e.gamma / 30));
      const gy = Math.max(-1, Math.min(1, (e.beta - 45) / 30)); // 45° ≈ natural hold
      target.current.x = gx * MAX_TILT;
      target.current.y = -gy * MAX_TILT * 0.7;
      kick();
    };

    wrap.addEventListener("pointermove", onPointerMove);
    wrap.addEventListener("pointerdown", onPointerDown);
    wrap.addEventListener("pointerup", onEnd);
    wrap.addEventListener("pointercancel", onEnd);
    wrap.addEventListener("pointerleave", onEnd);
    window.addEventListener("deviceorientation", onOrientation);

    return () => {
      wrap.removeEventListener("pointermove", onPointerMove);
      wrap.removeEventListener("pointerdown", onPointerDown);
      wrap.removeEventListener("pointerup", onEnd);
      wrap.removeEventListener("pointercancel", onEnd);
      wrap.removeEventListener("pointerleave", onEnd);
      window.removeEventListener("deviceorientation", onOrientation);
      if (raf.current) cancelAnimationFrame(raf.current);
    };
  }, []);

  return (
    <div
      ref={wrapRef}
      className="relative flex touch-pan-y items-center justify-center"
      style={{ perspective: "1000px" }}
    >
      {/* Ambient shadow beneath the band */}
      <div
        ref={shadowRef}
        aria-hidden
        className="absolute bottom-2 left-1/2 h-8 w-40 -translate-x-1/2 rounded-full bg-black/25 blur-xl"
        style={{ transform: "translateY(18px)" }}
      />
      <div className="relative" style={{ transformStyle: "preserve-3d" }}>
        <img
          ref={imgRef}
          src={src}
          alt={alt}
          width={1024}
          height={1024}
          draggable={false}
          className="h-48 w-48 select-none object-contain"
          style={{ transition: SPRING, transformStyle: "preserve-3d", willChange: "transform" }}
        />
        {/* Dynamic specular sheen */}
        <div
          ref={sheenRef}
          aria-hidden
          className="pointer-events-none absolute -inset-6 rounded-full opacity-0 mix-blend-screen"
          style={{ transition: "opacity 0.18s ease-out" }}
        />
      </div>
    </div>
  );
}
