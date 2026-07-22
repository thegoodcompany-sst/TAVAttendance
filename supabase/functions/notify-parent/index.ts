// notify-parent — PROD-02 (parent push notifications)
//
// Sends a push to the parents of a student when their attendance is marked
// `late` or `absent` (trigger on attendance_records, migration 021) or when
// they are `dismissed` (trigger on dismissals, migration 030), via pg_net —
// or callable directly with a JSON body. SHIPS DISABLED: it is a no-op unless the
// `push_notifications` feature flag is on, and requires APNs/FCM credentials that
// are provided out-of-band (see HUMANS.md).
//
// Deploy:  supabase functions deploy notify-parent
// Secrets: set NOTIFY_PARENT_INVOKE_SECRET to the same dedicated value stored
//          in Vault as notify_parent_invoke_secret; also set APNS_KEY=...
//          APNS_KEY_ID=... APNS_TEAM_ID=... (see HUMANS.md)
//          APNS_KEY is the full .p8 PEM. Optional: APNS_TOPIC (defaults to the app
//          bundle id), APNS_HOST (defaults to production; set
//          https://api.sandbox.push.apple.com for dev builds).
//          FCM (Android): FCM_SERVICE_ACCOUNT = the full Google service-account
//          JSON (Firebase console → Project settings → Service accounts).
// Tokens are routed by device_tokens.platform: 'ios' → APNs, 'android' → FCM.
// Each sender degrades gracefully when its secret is absent.

// deno-lint-ignore-file no-import-prefix -- Edge Functions pin JSR imports here.
import { createClient } from "jsr:@supabase/supabase-js@2.109.0";

interface Payload {
  student_id: string;
  status: "present" | "late" | "absent" | "excused" | "dismissed";
  session_id?: string;
  dismissal_id?: string;
}

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const NOTIFIABLE_STATUSES = new Set(["late", "absent", "dismissed"]);
const MAX_REQUEST_BYTES = 4 * 1024;
const MAX_SECRET_LENGTH = 512;
const GOOGLE_TOKEN_URI = "https://oauth2.googleapis.com/token";
const APNS_HOSTS = new Set([
  "https://api.push.apple.com",
  "https://api.sandbox.push.apple.com",
]);

async function secretsMatch(
  provided: string,
  expected: string,
): Promise<boolean> {
  const encoder = new TextEncoder();
  const [providedHash, expectedHash] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(provided)),
    crypto.subtle.digest("SHA-256", encoder.encode(expected)),
  ]);
  const left = new Uint8Array(providedHash);
  const right = new Uint8Array(expectedHash);
  let difference = left.length ^ right.length;
  for (let index = 0; index < Math.max(left.length, right.length); index++) {
    difference |= (left[index] ?? 0) ^ (right[index] ?? 0);
  }
  return difference === 0;
}

function parsePayload(raw: string): Payload | null {
  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch {
    return null;
  }

  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const body = value as Record<string, unknown>;
  if (
    typeof body.student_id !== "string" || !UUID_PATTERN.test(body.student_id)
  ) return null;
  if (
    typeof body.status !== "string" || !NOTIFIABLE_STATUSES.has(body.status)
  ) return null;
  if (
    body.session_id !== undefined &&
    (typeof body.session_id !== "string" || !UUID_PATTERN.test(body.session_id))
  ) return null;
  if (
    body.dismissal_id !== undefined &&
    (typeof body.dismissal_id !== "string" ||
      !UUID_PATTERN.test(body.dismissal_id))
  ) return null;

  return body as unknown as Payload;
}

const b64url = (data: Uint8Array | string): string => {
  const bytes = typeof data === "string"
    ? new TextEncoder().encode(data)
    : data;
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(
    /\//g,
    "_",
  ).replace(/=+$/, "");
};

/** ES256 JWT for token-based APNs auth. Apple caps JWT age at 60 min; this is a
 * short-lived function invocation, so a fresh token per call is fine. */
async function apnsJwt(
  p8Pem: string,
  keyId: string,
  teamId: string,
): Promise<string> {
  const pkcs8 = Uint8Array.from(
    atob(
      p8Pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(
        /\s/g,
        "",
      ),
    ),
    (c) => c.charCodeAt(0),
  );
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pkcs8,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const header = b64url(JSON.stringify({ alg: "ES256", kid: keyId }));
  const claims = b64url(
    JSON.stringify({ iss: teamId, iat: Math.floor(Date.now() / 1000) }),
  );
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(`${header}.${claims}`),
  );
  return `${header}.${claims}.${b64url(new Uint8Array(sig))}`;
}

/** OAuth2 access token for FCM HTTP v1, minted from the service-account JSON
 * (same in-function pattern as apnsJwt: sign a JWT, here RS256, then exchange
 * it at Google's token endpoint). Short-lived invocation → fresh token per call. */
async function fcmAccessToken(
  sa: { client_email: string; private_key: string; token_uri?: string },
): Promise<string> {
  const pkcs8 = Uint8Array.from(
    atob(
      sa.private_key.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(
        /\s/g,
        "",
      ),
    ),
    (c) => c.charCodeAt(0),
  );
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pkcs8,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const tokenUri = sa.token_uri ?? GOOGLE_TOKEN_URI;
  if (tokenUri !== GOOGLE_TOKEN_URI) {
    throw new Error("FCM token endpoint is not allowed");
  }
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: tokenUri,
    iat: now,
    exp: now + 3600,
  }));
  const sig = await crypto.subtle.sign(
    key.algorithm,
    key,
    new TextEncoder().encode(`${header}.${claims}`),
  );
  const jwt = `${header}.${claims}.${b64url(new Uint8Array(sig))}`;

  const res = await fetch(tokenUri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
    signal: AbortSignal.timeout(10_000),
  });
  if (!res.ok) {
    await res.body?.cancel();
    throw new Error(`FCM token exchange failed: ${res.status}`);
  }
  const { access_token } = await res.json();
  return access_token as string;
}

Deno.serve(async (req: Request) => {
  try {
    if (req.method !== "POST") {
      return Response.json(
        { error: "method not allowed" },
        { status: 405, headers: { Allow: "POST" } },
      );
    }

    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const invokeSecret = Deno.env.get("NOTIFY_PARENT_INVOKE_SECRET");
    if (
      !serviceKey || !supabaseUrl || !invokeSecret ||
      invokeSecret.length < 32 || invokeSecret.length > MAX_SECRET_LENGTH
    ) {
      return Response.json({ error: "service unavailable" }, { status: 503 });
    }

    // The gateway JWT check is disabled for this function because the database
    // trigger deliberately does not transmit the project-wide service-role
    // credential. This dedicated secret grants no database authority and is
    // checked here before any student/token lookup.
    if (req.headers.has("authorization")) {
      return Response.json({ error: "forbidden" }, { status: 403 });
    }
    const providedSecret = req.headers.get("x-notify-secret") ?? "";
    if (
      providedSecret.length > MAX_SECRET_LENGTH ||
      !(await secretsMatch(providedSecret, invokeSecret))
    ) {
      return Response.json({ error: "forbidden" }, { status: 403 });
    }

    const contentLength = Number(req.headers.get("content-length") ?? "0");
    if (Number.isFinite(contentLength) && contentLength > MAX_REQUEST_BYTES) {
      return Response.json({ error: "payload too large" }, { status: 413 });
    }

    const rawBody = await req.text();
    if (new TextEncoder().encode(rawBody).byteLength > MAX_REQUEST_BYTES) {
      return Response.json({ error: "payload too large" }, { status: 413 });
    }
    const body = parsePayload(rawBody);
    if (!body) {
      return Response.json({ error: "invalid payload" }, { status: 400 });
    }

    const supabase = createClient(supabaseUrl, serviceKey);

    // Gate: do nothing unless the feature flag is on.
    const { data: flag } = await supabase.rpc("is_feature_enabled", {
      p_key: "push_notifications",
    });
    if (flag !== true) {
      return Response.json({ skipped: "feature disabled" }, { status: 200 });
    }

    // Resolve parents → their device tokens.
    const { data: links, error: linksError } = await supabase
      .from("parent_student_links")
      .select("parent_id")
      .eq("student_id", body.student_id)
      .limit(20);
    if (linksError) throw new Error("parent link lookup failed");
    const parentIds = [...new Set((links ?? []).map((l) => l.parent_id))];
    if (parentIds.length === 0) {
      return Response.json({ sent: 0 }, { status: 200 });
    }

    // Fetch each parent's newest five native tokens independently. A global
    // legacy-row cap could otherwise let one parent starve a co-parent's
    // devices, and old web tokens must not consume native delivery capacity.
    const tokenResults = await Promise.all(parentIds.map((parentId) =>
      supabase
        .from("device_tokens")
        .select("token, platform")
        .eq("user_id", parentId)
        .in("platform", ["ios", "android"])
        .order("created_at", { ascending: false })
        .limit(5)
    ));
    if (tokenResults.some((result) => result.error)) {
      throw new Error("device token lookup failed");
    }
    const tokenRows = tokenResults.flatMap((result) => result.data ?? []);

    const sent = tokenRows.length;
    if (sent === 0) {
      return Response.json({ sent: 0, delivered: 0 }, { status: 200 });
    }

    // Each platform is initialized independently and only when it has tokens.
    // A malformed credential or provider outage on one side must not suppress
    // valid delivery through the other provider.
    const hasIosTokens = tokenRows.some((row) => row.platform === "ios");
    const hasAndroidTokens = tokenRows.some((row) =>
      row.platform === "android"
    );
    const apnsKey = Deno.env.get("APNS_KEY");
    const apnsKeyId = Deno.env.get("APNS_KEY_ID");
    const apnsTeamId = Deno.env.get("APNS_TEAM_ID");
    const apnsConfigured = !!(apnsKey && apnsKeyId && apnsTeamId);

    // Lock-screen notifications must not disclose a child's identity or status.
    // The authenticated parent dashboard contains the detailed update.
    const alertBody = body.status === "dismissed"
      ? "There is a dismissal update. Open TAVAttendance to review it."
      : "There is an attendance update. Open TAVAttendance to review it.";

    const topic = Deno.env.get("APNS_TOPIC") ?? "com.tava.TAVAttendance";
    const host = Deno.env.get("APNS_HOST") ?? "https://api.push.apple.com";
    let apnsAuth: string | null = null;
    let apnsSetupFailed = false;
    if (hasIosTokens && apnsConfigured) {
      try {
        if (!APNS_HOSTS.has(host)) throw new Error("invalid APNs host");
        apnsAuth = await apnsJwt(apnsKey!, apnsKeyId!, apnsTeamId!);
      } catch {
        apnsSetupFailed = true;
        console.error("notify-parent: APNs setup failed");
      }
    }

    type FcmServiceAccount = {
      project_id: string;
      client_email: string;
      private_key: string;
      token_uri?: string;
    };
    let fcmSa: FcmServiceAccount | null = null;
    let fcmAuth: string | null = null;
    let fcmSetupFailed = false;
    const fcmRaw = Deno.env.get("FCM_SERVICE_ACCOUNT");
    if (hasAndroidTokens && fcmRaw) {
      try {
        const parsed = JSON.parse(fcmRaw) as Record<string, unknown>;
        if (
          typeof parsed.project_id !== "string" || !parsed.project_id ||
          typeof parsed.client_email !== "string" || !parsed.client_email ||
          typeof parsed.private_key !== "string" || !parsed.private_key ||
          (parsed.token_uri !== undefined &&
            typeof parsed.token_uri !== "string")
        ) {
          throw new Error("invalid FCM service account");
        }
        fcmSa = {
          project_id: parsed.project_id,
          client_email: parsed.client_email,
          private_key: parsed.private_key,
          ...(parsed.token_uri ? { token_uri: parsed.token_uri } : {}),
        };
        fcmAuth = await fcmAccessToken(fcmSa);
      } catch {
        fcmSetupFailed = true;
        fcmSa = null;
        fcmAuth = null;
        console.error("notify-parent: FCM setup failed");
      }
    }

    type SendResult = {
      delivered: boolean;
      skipped?: string;
      invalid?: boolean;
    };
    const sendToken = async (
      t: { token: string; platform: string },
    ): Promise<SendResult> => {
      if (t.platform === "ios") {
        if (apnsSetupFailed) {
          return { delivered: false, skipped: "ios: setup failed" };
        }
        if (!apnsAuth) {
          return { delivered: false, skipped: "ios: apns not configured" };
        }
        const res = await fetch(
          `${host}/3/device/${encodeURIComponent(t.token)}`,
          {
            method: "POST",
            headers: {
              authorization: `bearer ${apnsAuth}`,
              "apns-topic": topic,
              "apns-push-type": "alert",
              "apns-priority": "10",
            },
            body: JSON.stringify({
              aps: {
                alert: { title: "TAVA Attendance", body: alertBody },
                sound: "default",
              },
            }),
            signal: AbortSignal.timeout(10_000),
          },
        );
        if (res.ok) {
          return { delivered: true };
        }
        const failure = await res.text();
        console.error(`notify-parent: APNs delivery failed (${res.status})`);
        return {
          delivered: false,
          invalid: res.status === 410 ||
            (res.status === 400 &&
              /BadDeviceToken|DeviceTokenNotForTopic/.test(failure)),
        };
      }
      if (t.platform === "android") {
        if (fcmSetupFailed) {
          return { delivered: false, skipped: "android: setup failed" };
        }
        if (!fcmAuth || !fcmSa) {
          return { delivered: false, skipped: "android: fcm not configured" };
        }
        const res = await fetch(
          `https://fcm.googleapis.com/v1/projects/${
            encodeURIComponent(fcmSa.project_id)
          }/messages:send`,
          {
            method: "POST",
            headers: {
              authorization: `Bearer ${fcmAuth}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              message: {
                token: t.token,
                notification: { title: "TAVA Attendance", body: alertBody },
                android: { priority: "HIGH" },
                // FCM data values must be strings; the Android client uses `type`
                // (and dismissal_id, when present) to land on the safely-home card.
                data: {
                  type: body.status,
                  ...(body.dismissal_id
                    ? { dismissal_id: body.dismissal_id }
                    : {}),
                },
              },
            }),
            signal: AbortSignal.timeout(10_000),
          },
        );
        if (res.ok) {
          return { delivered: true };
        }
        const failure = await res.text();
        console.error(`notify-parent: FCM delivery failed (${res.status})`);
        return {
          delivered: false,
          invalid: res.status === 404 || /UNREGISTERED/.test(failure),
        };
      }
      return { delivered: false, skipped: `${t.platform}: sender not wired` };
    };

    const safelySendToken = async (
      token: { token: string; platform: string },
    ): Promise<SendResult> => {
      try {
        return await sendToken(token);
      } catch {
        console.error(`notify-parent: ${token.platform} transport failed`);
        return {
          delivered: false,
          skipped: `${token.platform}: delivery failed`,
        };
      }
    };

    // Bound fan-out and latency. Registration and the per-parent fetch cap each
    // parent at five tokens; chunking also bounds outbound concurrency.
    let delivered = 0;
    const skipped: string[] = [];
    const invalidTokens: string[] = [];
    for (let offset = 0; offset < tokenRows.length; offset += 10) {
      const chunk = tokenRows.slice(offset, offset + 10);
      const results = await Promise.all(chunk.map(safelySendToken));
      results.forEach((result, index) => {
        if (result.delivered) delivered++;
        if (result.skipped) skipped.push(result.skipped);
        if (result.invalid) invalidTokens.push(chunk[index].token);
      });
    }
    if (invalidTokens.length > 0) {
      const { error: pruneError } = await supabase
        .from("device_tokens")
        .delete()
        .in("token", invalidTokens);
      if (pruneError) {
        console.error("notify-parent: stale-token cleanup failed");
      }
    }

    return Response.json({ sent, delivered, skipped }, { status: 200 });
  } catch (err) {
    console.error("notify-parent failed", err);
    return Response.json({ error: "internal error" }, { status: 500 });
  }
});
