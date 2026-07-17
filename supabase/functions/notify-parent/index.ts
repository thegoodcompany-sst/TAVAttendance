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
// Secrets: supabase secrets set APNS_KEY=... APNS_KEY_ID=... APNS_TEAM_ID=... (see HUMANS.md)
//          APNS_KEY is the full .p8 PEM. Optional: APNS_TOPIC (defaults to the app
//          bundle id), APNS_HOST (defaults to production; set
//          https://api.sandbox.push.apple.com for dev builds).
//          FCM (Android): FCM_SERVICE_ACCOUNT = the full Google service-account
//          JSON (Firebase console → Project settings → Service accounts).
// Tokens are routed by device_tokens.platform: 'ios' → APNs, 'android' → FCM.
// Each sender degrades gracefully when its secret is absent.

import { createClient } from 'jsr:@supabase/supabase-js@2'

interface Payload {
  student_id: string
  status: 'present' | 'late' | 'absent' | 'excused' | 'dismissed'
  session_id?: string
  dismissal_id?: string
}

const b64url = (data: Uint8Array | string): string => {
  const bytes = typeof data === 'string' ? new TextEncoder().encode(data) : data
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

/** ES256 JWT for token-based APNs auth. Apple caps JWT age at 60 min; this is a
 * short-lived function invocation, so a fresh token per call is fine. */
async function apnsJwt(p8Pem: string, keyId: string, teamId: string): Promise<string> {
  const pkcs8 = Uint8Array.from(
    atob(p8Pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, '').replace(/\s/g, '')),
    (c) => c.charCodeAt(0),
  )
  const key = await crypto.subtle.importKey(
    'pkcs8', pkcs8, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign'],
  )
  const header = b64url(JSON.stringify({ alg: 'ES256', kid: keyId }))
  const claims = b64url(JSON.stringify({ iss: teamId, iat: Math.floor(Date.now() / 1000) }))
  const sig = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(`${header}.${claims}`),
  )
  return `${header}.${claims}.${b64url(new Uint8Array(sig))}`
}

/** OAuth2 access token for FCM HTTP v1, minted from the service-account JSON
 * (same in-function pattern as apnsJwt: sign a JWT, here RS256, then exchange
 * it at Google's token endpoint). Short-lived invocation → fresh token per call. */
async function fcmAccessToken(sa: { client_email: string; private_key: string; token_uri?: string }): Promise<string> {
  const pkcs8 = Uint8Array.from(
    atob(sa.private_key.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, '').replace(/\s/g, '')),
    (c) => c.charCodeAt(0),
  )
  const key = await crypto.subtle.importKey(
    'pkcs8', pkcs8, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'],
  )
  const tokenUri = sa.token_uri ?? 'https://oauth2.googleapis.com/token'
  const now = Math.floor(Date.now() / 1000)
  const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))
  const claims = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: tokenUri,
    iat: now,
    exp: now + 3600,
  }))
  const sig = await crypto.subtle.sign(key.algorithm, key, new TextEncoder().encode(`${header}.${claims}`))
  const jwt = `${header}.${claims}.${b64url(new Uint8Array(sig))}`

  const res = await fetch(tokenUri, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  })
  if (!res.ok) throw new Error(`FCM token exchange failed: ${res.status} ${await res.text()}`)
  const { access_token } = await res.json()
  return access_token as string
}

Deno.serve(async (req: Request) => {
  try {
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!serviceKey) {
      return Response.json({ error: 'service unavailable' }, { status: 503 })
    }

    // This function is server-to-server only: it is invoked by the DB trigger
    // (pg_net) with the service-role key, and it exposes which students have
    // linked parents / device tokens. Reject any other caller so an ordinary
    // authenticated user cannot enumerate that via the bearer token.
    const auth = req.headers.get('Authorization') ?? ''
    if (auth !== `Bearer ${serviceKey}`) {
      return Response.json({ error: 'forbidden' }, { status: 403 })
    }

    const supabase = createClient(Deno.env.get('SUPABASE_URL')!, serviceKey)

    // Gate: do nothing unless the feature flag is on.
    const { data: flag } = await supabase.rpc('is_feature_enabled', {
      p_key: 'push_notifications',
    })
    if (flag !== true) {
      return Response.json({ skipped: 'feature disabled' }, { status: 200 })
    }

    const body = (await req.json()) as Payload
    if (body.status !== 'late' && body.status !== 'absent' && body.status !== 'dismissed') {
      return Response.json({ skipped: 'status not notifiable' }, { status: 200 })
    }

    // Resolve parents → their device tokens.
    const { data: links } = await supabase
      .from('parent_student_links')
      .select('parent_id')
      .eq('student_id', body.student_id)
    const parentIds = (links ?? []).map((l) => l.parent_id)
    if (parentIds.length === 0) {
      return Response.json({ sent: 0 }, { status: 200 })
    }

    const { data: tokens } = await supabase
      .from('device_tokens')
      .select('token, platform')
      .in('user_id', parentIds)

    const sent = (tokens ?? []).length
    if (sent === 0) {
      return Response.json({ sent: 0, delivered: 0 }, { status: 200 })
    }

    // Inert without credentials: deploying this function with no secrets set is safe.
    // Each platform's sender is independently optional.
    const apnsKey = Deno.env.get('APNS_KEY')
    const apnsKeyId = Deno.env.get('APNS_KEY_ID')
    const apnsTeamId = Deno.env.get('APNS_TEAM_ID')
    const apnsConfigured = !!(apnsKey && apnsKeyId && apnsTeamId)

    const fcmRaw = Deno.env.get('FCM_SERVICE_ACCOUNT')
    const fcmSa = fcmRaw
      ? (JSON.parse(fcmRaw) as { project_id: string; client_email: string; private_key: string; token_uri?: string })
      : null

    if (!apnsConfigured && !fcmSa) {
      console.log(`notify-parent: would send ${sent} push(es); sender credentials not configured`)
      return Response.json({ sent, delivered: 0, note: 'senders not configured' }, { status: 200 })
    }

    // Lock-screen notifications must not disclose a child's identity or status.
    // The authenticated parent dashboard contains the detailed update.
    const alertBody = body.status === 'dismissed'
      ? 'There is a dismissal update. Open TAVAttendance to review it.'
      : 'There is an attendance update. Open TAVAttendance to review it.'

    const apnsAuth = apnsConfigured ? await apnsJwt(apnsKey!, apnsKeyId!, apnsTeamId!) : null
    const topic = Deno.env.get('APNS_TOPIC') ?? 'com.tava.TAVAttendance'
    const host = Deno.env.get('APNS_HOST') ?? 'https://api.push.apple.com'
    const fcmAuth = fcmSa ? await fcmAccessToken(fcmSa) : null

    let delivered = 0
    const skipped: string[] = []
    for (const t of tokens ?? []) {
      if (t.platform === 'ios') {
        if (!apnsAuth) {
          skipped.push('ios: apns not configured')
          continue
        }
        const res = await fetch(`${host}/3/device/${t.token}`, {
          method: 'POST',
          headers: {
            authorization: `bearer ${apnsAuth}`,
            'apns-topic': topic,
            'apns-push-type': 'alert',
            'apns-priority': '10',
          },
          body: JSON.stringify({ aps: { alert: { title: 'TAVA Attendance', body: alertBody }, sound: 'default' } }),
        })
        if (res.ok) {
          delivered++
        } else {
          // Consume the body so the connection can be reused; log Apple's reason.
          console.error(`notify-parent: APNs ${res.status} — ${await res.text()}`)
        }
      } else if (t.platform === 'android') {
        if (!fcmAuth || !fcmSa) {
          skipped.push('android: fcm not configured')
          continue
        }
        const res = await fetch(`https://fcm.googleapis.com/v1/projects/${fcmSa.project_id}/messages:send`, {
          method: 'POST',
          headers: {
            authorization: `Bearer ${fcmAuth}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            message: {
              token: t.token,
              notification: { title: 'TAVA Attendance', body: alertBody },
              android: { priority: 'HIGH' },
              // FCM data values must be strings; the Android client uses `type`
              // (and dismissal_id, when present) to land on the safely-home card.
              data: {
                type: body.status,
                ...(body.dismissal_id ? { dismissal_id: body.dismissal_id } : {}),
              },
            },
          }),
        })
        if (res.ok) {
          delivered++
        } else {
          console.error(`notify-parent: FCM ${res.status} — ${await res.text()}`)
        }
      } else {
        skipped.push(`${t.platform}: sender not wired`)
      }
    }

    return Response.json({ sent, delivered, skipped }, { status: 200 })
  } catch (err) {
    return Response.json({ error: String(err) }, { status: 500 })
  }
})
