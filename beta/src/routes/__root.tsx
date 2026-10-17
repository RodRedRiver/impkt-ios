import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import {
  Outlet,
  Link,
  createRootRouteWithContext,
  useRouter,
  useRouterState,
  HeadContent,
  Scripts,
} from "@tanstack/react-router";
import type { ErrorComponentProps } from "@tanstack/react-router";
import { Activity, BarChart3, Clock, Settings as SettingsIcon } from "lucide-react";
import { useEffect, type ReactNode } from "react";

import appCss from "../styles.css?url";
import { reportLovableError } from "../lib/lovable-error-reporting";
import { SettingsProvider } from "../lib/settings";
import { Toaster } from "../components/ui/sonner";
import { UpdateWatcher } from "../components/UpdateWatcher";
import { IN_APP } from "../lib/band";
import { BetaWelcome } from "../components/BetaWelcome";

function NotFoundComponent() {
  return (
    <div className="flex min-h-screen items-center justify-center px-6">
      <div className="glass max-w-sm p-8 text-center">
        <h1 className="tnum text-5xl font-semibold">404</h1>
        <p className="mt-3 text-sm text-muted-foreground">This screen doesn't exist.</p>
        <Link
          to="/"
          className="mt-6 inline-flex rounded-full bg-primary px-5 py-2.5 text-sm font-medium text-primary-foreground"
        >
          Go to Train
        </Link>
      </div>
    </div>
  );
}

function ErrorComponent({ error, reset }: ErrorComponentProps) {
  console.error(error);
  const router = useRouter();
  useEffect(() => {
    reportLovableError(error, { boundary: "tanstack_root_error_component" });
  }, [error]);

  return (
    <div className="flex min-h-screen items-center justify-center px-6">
      <div className="glass max-w-sm p-8 text-center">
        <h1 className="text-lg font-semibold">This screen didn't load</h1>
        <p className="mt-2 text-sm text-muted-foreground">Try again or head back to Train.</p>
        <div className="mt-6 flex flex-wrap justify-center gap-2">
          <button
            onClick={() => {
              router.invalidate();
              reset();
            }}
            className="rounded-full bg-primary px-5 py-2.5 text-sm font-medium text-primary-foreground"
          >
            Try again
          </button>
          <a href="/" className="rounded-full border border-border px-5 py-2.5 text-sm font-medium">
            Train
          </a>
        </div>
      </div>
    </div>
  );
}

export const Route = createRootRouteWithContext<{ queryClient: QueryClient }>()({
  head: () => ({
    meta: [
      { charSet: "utf-8" },
      {
        name: "viewport",
        content: "width=device-width, initial-scale=1, viewport-fit=cover, user-scalable=yes",
      },
      { name: "theme-color", content: "#0B0C10" },
      { name: "mobile-web-app-capable", content: "yes" },
      { name: "apple-mobile-web-app-capable", content: "yes" },
      { name: "apple-mobile-web-app-status-bar-style", content: "black-translucent" },
      { name: "apple-mobile-web-app-title", content: "IMPKT" },
      { name: "application-name", content: "IMPKT" },
      { name: "msapplication-TileColor", content: "#0B0C10" },
      { name: "msapplication-navbutton-color", content: "#0B0C10" },
      { name: "msapplication-TileImage", content: "/icons/icon-192.png" },
      { name: "msapplication-config", content: "none" },
      { name: "color-scheme", content: "dark light" },
      { title: "IMPKT — BOXING-01 companion app" },
      {
        name: "description",
        content: "Record boxing sessions with the BOXING-01 wrist sensor and review honest metrics.",
      },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary_large_image" },
    ],
    links: [
      // Inter from Google is the web build's fallback face. The app on an iPhone draws SF,
      // which comes first in --font-sans, and must not wait on the network for a font it
      // will not use: a gym with no signal would get a blank tab until the request gave up.
      ...(IN_APP
        ? []
        : [
            { rel: "preconnect", href: "https://fonts.googleapis.com" },
            { rel: "preconnect", href: "https://fonts.gstatic.com", crossOrigin: "anonymous" as const },
            {
              rel: "stylesheet",
              href: "https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap",
            },
          ]),
      { rel: "stylesheet", href: appCss },
      { rel: "manifest", href: "/manifest.webmanifest" },
      { rel: "icon", href: "/icons/favicon.png", type: "image/png", sizes: "64x64" },
      { rel: "apple-touch-icon", href: "/icons/apple-touch-icon.png", sizes: "180x180" },
      {
        rel: "apple-touch-startup-image",
        href: "/splash/iphone-se-640x1136.png",
        media: "(device-width: 320px) and (device-height: 568px) and (-webkit-device-pixel-ratio: 2) and (orientation: portrait)",
      },
      {
        rel: "apple-touch-startup-image",
        href: "/splash/iphone-8-750x1334.png",
        media: "(device-width: 375px) and (device-height: 667px) and (-webkit-device-pixel-ratio: 2) and (orientation: portrait)",
      },
      {
        rel: "apple-touch-startup-image",
        href: "/splash/iphone-xr-828x1792.png",
        media: "(device-width: 414px) and (device-height: 896px) and (-webkit-device-pixel-ratio: 2) and (orientation: portrait)",
      },
      {
        rel: "apple-touch-startup-image",
        href: "/splash/iphone-x-1125x2436.png",
        media: "(device-width: 375px) and (device-height: 812px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)",
      },
      {
        rel: "apple-touch-startup-image",
        href: "/splash/iphone-12-1170x2532.png",
        media: "(device-width: 390px) and (device-height: 844px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)",
      },
      {
        rel: "apple-touch-startup-image",
        href: "/splash/iphone-14-pro-1179x2556.png",
        media: "(device-width: 393px) and (device-height: 852px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)",
      },
      {
        rel: "apple-touch-startup-image",
        href: "/splash/iphone-8-plus-1242x2208.png",
        media: "(device-width: 414px) and (device-height: 736px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)",
      },
      {
        rel: "apple-touch-startup-image",
        href: "/splash/iphone-xs-max-1242x2688.png",
        media: "(device-width: 414px) and (device-height: 896px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)",
      },
      {
        rel: "apple-touch-startup-image",
        href: "/splash/iphone-12-pro-max-1284x2778.png",
        media: "(device-width: 428px) and (device-height: 926px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)",
      },
      {
        rel: "apple-touch-startup-image",
        href: "/splash/iphone-14-pro-max-1290x2796.png",
        media: "(device-width: 430px) and (device-height: 932px) and (-webkit-device-pixel-ratio: 3) and (orientation: portrait)",
      },
      {
        rel: "apple-touch-startup-image",
        href: "/splash/ipad-9-7-1536x2048.png",
        media: "(device-width: 768px) and (device-height: 1024px) and (-webkit-device-pixel-ratio: 2) and (orientation: portrait)",
      },
      {
        rel: "apple-touch-startup-image",
        href: "/splash/ipad-9-7-2048x1536.png",
        media: "(device-width: 768px) and (device-height: 1024px) and (-webkit-device-pixel-ratio: 2) and (orientation: landscape)",
      },
      {
        rel: "apple-touch-startup-image",
        href: "/splash/ipad-10-5-1668x2224.png",
        media: "(device-width: 834px) and (device-height: 1112px) and (-webkit-device-pixel-ratio: 2) and (orientation: portrait)",
      },
      {
        rel: "apple-touch-startup-image",
        href: "/splash/ipad-10-5-2224x1668.png",
        media: "(device-width: 834px) and (device-height: 1112px) and (-webkit-device-pixel-ratio: 2) and (orientation: landscape)",
      },
      {
        rel: "apple-touch-startup-image",
        href: "/splash/ipad-11-1668x2388.png",
        media: "(device-width: 834px) and (device-height: 1194px) and (-webkit-device-pixel-ratio: 2) and (orientation: portrait)",
      },
      {
        rel: "apple-touch-startup-image",
        href: "/splash/ipad-11-2388x1668.png",
        media: "(device-width: 834px) and (device-height: 1194px) and (-webkit-device-pixel-ratio: 2) and (orientation: landscape)",
      },
      {
        rel: "apple-touch-startup-image",
        href: "/splash/ipad-12-9-2048x2732.png",
        media: "(device-width: 1024px) and (device-height: 1366px) and (-webkit-device-pixel-ratio: 2) and (orientation: portrait)",
      },
      {
        rel: "apple-touch-startup-image",
        href: "/splash/ipad-12-9-2732x2048.png",
        media: "(device-width: 1024px) and (device-height: 1366px) and (-webkit-device-pixel-ratio: 2) and (orientation: landscape)",
      },
    ],

  }),
  shellComponent: RootShell,
  component: RootComponent,
  notFoundComponent: NotFoundComponent,
  errorComponent: ErrorComponent,
});

function RootShell({ children }: { children: ReactNode }) {
  return (
    <html lang="en" className="dark">
      <head>
        <HeadContent />
      </head>
      <body>
        {children}
        <Scripts />
      </body>
    </html>
  );
}

const tabs = [
  { to: "/", label: "Train", icon: Activity },
  { to: "/session", label: "Session", icon: BarChart3 },
  { to: "/history", label: "History", icon: Clock },
  { to: "/settings", label: "Settings", icon: SettingsIcon },
] as const;

function RootComponent() {
  const { queryClient } = Route.useRouteContext();
  const pathname = useRouterState({ select: (s) => s.location.pathname });
  const immersive = pathname === "/record";

  return (
    <QueryClientProvider client={queryClient}>
      <SettingsProvider>
        {/* Train paints its own light ground; the dark bloom would tint it. */}
        {pathname === "/" ? null : <div className="bloom" aria-hidden />}
        <div className={pathname === "/" ? "train-light-shell mx-auto flex min-h-screen w-full max-w-md flex-col" : "mx-auto flex min-h-screen w-full max-w-md flex-col"}>
          <main className={immersive ? "flex-1 pt-[env(safe-area-inset-top)]" : "flex-1 pb-28 pt-[env(safe-area-inset-top)]"}>
            {/* Required: nested routes render here. */}
            <Outlet />
          </main>
          {immersive ? null : (
            <nav className="fixed inset-x-0 bottom-0 z-20 px-3 pb-[max(12px,env(safe-area-inset-bottom))]">
              <div className="glass app-tab-bar mx-auto flex w-full max-w-md items-stretch rounded-full p-1.5">
                {tabs.map(({ to, label, icon: Icon }) => (
                  <Link
                    key={to}
                    to={to}
                    activeOptions={{ exact: to === "/" }}
                    className="flex flex-1 flex-col items-center gap-1 rounded-full py-2 text-muted-foreground transition-colors"
                    activeProps={{ className: "bg-primary/10 !text-primary" }}
                  >
                    <Icon className="h-5 w-5" strokeWidth={1.75} />
                    <span className="text-[10px] font-medium">{label}</span>
                  </Link>
                ))}
              </div>
            </nav>
          )}
        </div>
        <Toaster position="top-center" />
        {IN_APP ? <BetaWelcome /> : null}
        {/* The app ships a new copy of this page with each build, and has no server to poll. */}
        {IN_APP ? null : <UpdateWatcher />}
      </SettingsProvider>
    </QueryClientProvider>
  );
}
