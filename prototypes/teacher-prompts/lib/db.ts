import "server-only";
import { Pool, type QueryResult } from "pg";
import { databaseConfig } from "./config";
import { asIdentity } from "./transaction";
const globalDb = globalThis as unknown as { tpPool?: Pool };
const pool = globalDb.tpPool ?? new Pool(databaseConfig(process.env));
globalDb.tpPool = pool;
export async function queryAs<T>(
  identity: string,
  sql: string,
  values: unknown[],
): Promise<T> {
  return asIdentity(await pool.connect(), identity, async (client) => {
    const result = (await client.query(sql, values)) as QueryResult<{
      result: T;
    }>;
    return result.rows[0].result;
  });
}
