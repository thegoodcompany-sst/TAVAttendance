import "server-only";
import { Pool, type QueryResult } from "pg";
import { databaseConfig } from "./config";
import { verifyDemoMarker } from "./demo-marker";
import { requirePreviewAccess } from "./access";
import { asIdentity } from "./transaction";
const globalDb = globalThis as unknown as { tpPool?: Pool };
function getPool() {
  return (globalDb.tpPool ??= new Pool(databaseConfig(process.env)));
}
export async function ensureDemoDatabase() {
  await verifyDemoMarker(getPool());
}
export async function queryAs<T>(
  identity: string,
  sql: string,
  values: unknown[],
): Promise<T> {
  await requirePreviewAccess();
  await ensureDemoDatabase();
  return asIdentity(await getPool().connect(), identity, async (client) => {
    const result = (await client.query(sql, values)) as QueryResult<{
      result: T;
    }>;
    return result.rows[0].result;
  });
}
