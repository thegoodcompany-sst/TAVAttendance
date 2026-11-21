import pg from "pg";
import type { PoolClient } from "pg";
import { RpcPromptDb, type WorkerRpc } from "./prompt-db.ts";

export function localDatabaseConfig(rawUrl: string | undefined, assignedName: string | undefined) {
  if (!assignedName || !/^tp_[a-z0-9_]{1,60}$/.test(assignedName) ||
    ["postgres", "template0", "template1"].includes(assignedName) ||
    rawUrl !== `postgresql://postgres@localhost:55432/${assignedName}`) {
    throw new Error("TP_LOCAL_DATABASE_REQUIRED");
  }
  // Explicit connection fields; never inherit PGHOST/PGPASSWORD/service files.
  return { host: "localhost", port: 55432, user: "postgres", password: "", database: assignedName,
    ssl: false as const, max: 5, connectionTimeoutMillis: 5_000, idleTimeoutMillis: 5_000,
    statement_timeout: 10_000, application_name: "teacher-prompts-dry-run" };
}

const statements: Record<WorkerRpc, { sql: string; args: string[] }> = {
  scheduler_tick: {
    sql: "SELECT * FROM public.scheduler_tick($1::timestamptz,$2::int)", args: ["p_now", "p_limit"],
  },
  prepare_prompt_delivery: {
    sql: "SELECT public.prepare_prompt_delivery($1::uuid,$2::uuid,$3::timestamptz) AS result",
    args: ["p_outbox_id", "p_lease_token", "p_now"],
  },
  mark_prompt_sent: {
    sql: "SELECT public.mark_prompt_sent($1::uuid,$2::uuid,$3::uuid,$4::text,$5::timestamptz) AS result",
    args: ["p_outbox_id", "p_lease_token", "p_provider_id", "p_transport", "p_now"],
  },
  mark_prompt_failed: {
    sql: "SELECT public.mark_prompt_failed($1::uuid,$2::uuid,$3::text,$4::boolean,$5::boolean,$6::timestamptz) AS result",
    args: ["p_outbox_id", "p_lease_token", "p_error_code", "p_retryable", "p_invalidate_device", "p_now"],
  },
};

export class LocalPromptDb extends RpcPromptDb {
  private pool: pg.Pool;
  constructor(rawUrl: string | undefined, assignedName: string | undefined) {
    const pool = new pg.Pool(localDatabaseConfig(rawUrl, assignedName));
    super(async (name, args) => this.transaction(async (client) => {
      const statement = statements[name];
      const result = await client.query(statement.sql, statement.args.map((key) => args[key]));
      if (name !== "scheduler_tick") return result.rows[0]?.result;
      return result.rows.map((row) => ({ ...row,
        plan_revision: String(row.plan_revision),
        lease_until: row.lease_until instanceof Date ? row.lease_until.toISOString() : row.lease_until,
      }));
    }));
    this.pool = pool;
    // The event must be handled, but a driver error may contain credentials or data.
    this.pool.on("error", () => {});
  }

  private async transaction<T>(operation: (client: PoolClient) => Promise<T>): Promise<T> {
    const client = await this.pool.connect().catch(() => { throw new Error("TP_DATABASE_ERROR"); });
    let broken = false;
    try {
      await client.query("BEGIN");
      await client.query("SET LOCAL ROLE service_role");
      const result = await operation(client);
      await client.query("COMMIT");
      return result;
    } catch {
      try { await client.query("ROLLBACK"); } catch { broken = true; }
      throw new Error("TP_DATABASE_ERROR");
    } finally { client.release(broken); }
  }

  async isDemo(): Promise<boolean> {
    return this.transaction(async (client) => {
      const result = await client.query("SELECT demo_enabled FROM public.runtime_settings WHERE id = true");
      return result.rows[0]?.demo_enabled === true;
    });
  }
  async refresh(): Promise<void> {
    await this.transaction(async (client) => { await client.query("SELECT public.refresh_prompt_schedule()"); });
  }
  async close(): Promise<void> { await this.pool.end(); }
}
