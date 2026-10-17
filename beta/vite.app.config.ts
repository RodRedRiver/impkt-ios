// The build that goes inside the iOS app, as its Beta tab. `npm run build:app`.
//
// The same project and the same routes as the Lovable web build in vite.config.ts,
// with two differences. It is a single-page app, prerendered to one shell, because the
// app serves files out of its bundle and has no server to render on. And it skips
// nitro, which is the Cloudflare deploy.
//
// It is served at the root of its own host, impkt://beta/, rather than under a path of
// the Test tab's impkt://app. The router's basepath is a URL rewrite, and the rewrite
// calls any URL that is not http or https external, so under a basepath every tap on
// impkt:// became a document load to a scheme the router then refuses: nothing moved.
import { defineConfig } from "@lovable.dev/vite-tanstack-config";

export default defineConfig({
  nitro: false,
  tanstackStart: {
    server: { entry: "server" },
    spa: {
      enabled: true,
      prerender: { outputPath: "/index.html", crawlLinks: false },
    },
  },
  vite: {
    build: { outDir: "dist-app", emptyOutDir: true },
  },
});
