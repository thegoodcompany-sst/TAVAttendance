"use node";

import { connect, constants } from "node:http2";
import type { ApnsFetch } from "./apns_sender.ts";
import { UUID_PATTERN } from "./prompt_payload.ts";

/** Actual HTTP/2, supported by Deno's node compatibility layer. Never used in tests.
 * No redirects, HTTP/1 fallback, arbitrary destination, or response-body logging.
 */
export const http2Fetch: ApnsFetch = async (input, init) => {
  const url = new URL(input);
  if (
    ![
      "https://api.push.apple.com",
      "https://api.sandbox.push.apple.com",
    ].includes(url.origin) ||
    url.username ||
    url.password ||
    url.search ||
    url.hash ||
    !/^\/3\/device\/(?:[0-9a-f]{2}){16,256}$/.test(url.pathname) ||
    init.method !== "POST"
  ) {
    throw new Error("TP_INVALID_TRANSPORT_REQUEST");
  }
  return new Promise<Response>((resolve, reject) => {
    if (init.signal?.aborted) {
      reject(new Error("TP_TRANSPORT_ABORTED"));
      return;
    }
    const session = connect(url.origin, { ALPNProtocols: ["h2"] });
    let finished = false;
    let status = 0;
    let responseHeaders = new Headers();
    const chunks: Uint8Array[] = [];
    let size = 0;
    const request = session.request({
      ...Object.fromEntries(new Headers(init.headers)),
      [constants.HTTP2_HEADER_METHOD]: "POST",
      [constants.HTTP2_HEADER_PATH]: url.pathname,
    });
    const finish = (error?: boolean) => {
      if (finished) return;
      finished = true;
      init.signal?.removeEventListener("abort", abort);
      clearTimeout(timer);
      request.close();
      session.destroy();
      if (error || status < 200 || status > 599) {
        reject(new Error("TP_TRANSPORT_ERROR"));
        return;
      }
      const bytes = new Uint8Array(size);
      let offset = 0;
      for (const chunk of chunks) {
        bytes.set(chunk, offset);
        offset += chunk.length;
      }
      resolve(
        new Response([204, 205, 304].includes(status) ? null : bytes, {
          status,
          headers: responseHeaders,
        }),
      );
    };
    const abort = () => finish(true);
    const timer = setTimeout(abort, 10_000);
    init.signal?.addEventListener("abort", abort, { once: true });
    session.on("error", abort);
    request.on("error", abort);
    request.on("aborted", abort);
    request.on("close", () => {
      if (!finished) finish(true);
    });
    request.on("response", (headers) => {
      status = Number(headers[":status"]);
      responseHeaders = new Headers();
      const providerId = headers["apns-id"];
      if (
        typeof providerId === "string" &&
        UUID_PATTERN.test(providerId.toLowerCase())
      )
        responseHeaders.set("apns-id", providerId);
    });
    request.on("data", (chunk: Uint8Array) => {
      size += chunk.byteLength;
      if (size > 1024) {
        finish(true);
        return;
      }
      chunks.push(chunk);
    });
    request.on("end", () => finish());
    request.end(init.body);
  });
};
