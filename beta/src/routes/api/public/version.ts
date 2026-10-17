import { createFileRoute } from "@tanstack/react-router";

// Generated once per server start / deployment. A new deployment boots a new
// worker instance, so this value changes whenever a new build goes live.
const BUILD_ID = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;

export const Route = createFileRoute("/api/public/version")({
  server: {
    handlers: {
      GET: async () =>
        new Response(JSON.stringify({ version: BUILD_ID }), {
          headers: {
            "content-type": "application/json",
            "cache-control": "no-store, no-cache, must-revalidate",
          },
        }),
    },
  },
});
