import { Pool } from "pg";
import { spawn } from "node:child_process";
import { databaseConfig } from "../lib/config";
const pool = new Pool(databaseConfig(process.env));
try {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SET LOCAL ROLE service_role");
    const result = await client.query(
      "SELECT demo_enabled FROM public.runtime_settings WHERE id=true",
    );
    if (result.rows[0]?.demo_enabled !== true)
      throw new Error("TP_DEMO_REQUIRED");
    await client.query("COMMIT");
  } finally {
    client.release();
  }
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
