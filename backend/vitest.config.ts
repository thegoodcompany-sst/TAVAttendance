import wasmModule from "vite-plugin-wasm-module";
import { defineConfig } from "vitest/config";
export default defineConfig({
  plugins: [wasmModule()],
  test: {
    environment: "edge-runtime",
    env: { CONVEX_CLOUD_URL: "https://some-deployment.convex.cloud" },
    server: { deps: { inline: ["convex-test", "password-hash-wasm"] } },
  },
});
