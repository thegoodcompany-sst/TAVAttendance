import { RpcPromptDb } from "./prompt-db.ts";

/** Hosted adapter for a later reviewed deployment. No requests on import/construction. */
export class RestPromptDb extends RpcPromptDb {
  constructor(baseUrl: string, serviceKey: string, fetchRpc: typeof fetch) {
    const url = new URL(baseUrl);
    if (!serviceKey || url.protocol !== "https:" || url.username || url.password || url.search || url.hash || url.pathname !== "/") {
      throw new Error("TP_INVALID_DATABASE_CONFIG");
    }
    super(async (name, args) => {
      try {
        const response = await fetchRpc(`${url.origin}/rest/v1/rpc/${name}`, {
          method: "POST", redirect: "error", signal: AbortSignal.timeout(10_000),
          headers: { "content-type": "application/json", apikey: serviceKey, authorization: `Bearer ${serviceKey}` },
          body: JSON.stringify(args),
        });
        if (!response.ok) { await response.body?.cancel(); throw new Error("TP_DATABASE_ERROR"); }
        return await response.json();
      } catch { throw new Error("TP_DATABASE_ERROR"); }
    });
  }
}
