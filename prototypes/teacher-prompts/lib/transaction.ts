import { demoIdentity } from "./identity";
export interface Client {
  query(text: string, values?: unknown[]): Promise<unknown>;
  release(): void;
}
export async function asIdentity<T>(
  client: Client,
  identity: string,
  work: (client: Client) => Promise<T>,
): Promise<T> {
  try {
    if (!demoIdentity(identity)) throw new Error("TP_NOT_AVAILABLE");
    await client.query("BEGIN");
    await client.query("SET LOCAL ROLE authenticated");
    await client.query("SELECT set_config('request.jwt.claims', $1, true)", [
      JSON.stringify({ sub: identity, role: "authenticated" }),
    ]);
    const result = await work(client);
    await client.query("COMMIT");
    return result;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}
