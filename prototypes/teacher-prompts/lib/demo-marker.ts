import type { Pool } from "pg";
export async function verifyDemoMarker(pool: Pick<Pool, "connect">) {
  const client = await pool.connect().catch(() => {
    throw new Error("TP_DEMO_REQUIRED");
  });
  try {
    await client.query("BEGIN");
    await client.query("SET LOCAL ROLE service_role");
    const result = await client.query(
      "SELECT demo_enabled FROM public.runtime_settings WHERE id=true",
    );
    if (result.rows[0]?.demo_enabled !== true)
      throw new Error("TP_DEMO_REQUIRED");
    await client.query("COMMIT");
  } catch {
    await client.query("ROLLBACK").catch(() => {});
    throw new Error("TP_DEMO_REQUIRED");
  } finally {
    client.release();
  }
}

/** Never publish a request pool until the demo marker succeeds. Close on failure. */
export async function verifiedDemoPool<T extends Pick<Pool, "connect" | "end">>(
  pool: T,
): Promise<T> {
  try {
    await verifyDemoMarker(pool);
    return pool;
  } catch {
    await pool.end().catch(() => {});
    throw new Error("TP_DEMO_REQUIRED");
  }
}
