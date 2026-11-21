import { verifyDemoMarker } from "../lib/demo-marker";
import { Pool } from "pg";
import { spawn } from "node:child_process";
import { databaseConfig } from "../lib/config";
const pool = new Pool(databaseConfig(process.env));
try {
  await verifyDemoMarker(pool);
} catch {
  process.stderr.write("TP_STARTUP_CHECK_FAILED\n");
  process.exit(1);
} finally {
  await pool.end();
}
const child = spawn(
  process.execPath,
  [
    "--bun",
    "node_modules/next/dist/bin/next",
    process.argv[2] ?? "dev",
    "--hostname",
    "127.0.0.1",
    "--port",
    "3100",
  ],
  { stdio: "inherit", env: { ...process.env, NEXT_TELEMETRY_DISABLED: "1" } },
);
for (const signal of ["SIGINT", "SIGTERM"] as const)
  process.on(signal, () => child.kill(signal));
child.on("exit", (code) => process.exit(code ?? 0));
