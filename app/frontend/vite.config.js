import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// In dev, /api is proxied to a local API; in the cluster, Traefik routes /api to the API service.
export default defineConfig({
  plugins: [react()],
  server: { proxy: { "/api": "http://localhost:8080" } },
});
