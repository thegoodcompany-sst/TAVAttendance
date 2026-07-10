// notify-parent — PROD-02 (parent push notifications)
//
// Sends a push to the parents of a student when their attendance is marked
// `late` or `absent`. Invoked by a DB trigger (via pg_net) on attendance_records,
// or callable directly with a JSON body. SHIPS DISABLED: it is a no-op unless the
// `push_notifications` feature flag is on, and requires APNs/FCM credentials that
// are provided out-of-band (see HUMANS.md).
//
// Deploy:  supabase functions deploy notify-parent
// Secrets: supabase secrets set APNS_KEY=... APNS_KEY_ID=... APNS_TEAM_ID=... (see HUMANS.md)
//          APNS_KEY is the full .p8 PEM. Optional: APNS_TOPIC (defaults to the app
//          bundle id), APNS_HOST (defaults to production; set
//          https://api.sandbox.push.apple.com for dev builds).
// FCM (Android) is deliberately not wired: the Android app has no FCM registration
// yet, so an 'android' device_tokens row cannot exist. Wire it with the Android port.

import { createClient } from 'jsr:@supabase/supabase-js@2'

interface Payload {
  student_id: string
  status: 'present' | 'late' | 'absent' | 'excused'
  session_id?: string
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

Deno.serve(async (req: Request) => {
  try {
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

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
    if (body.status !== 'late' && body.status !== 'absent') {
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
    const apnsKey = Deno.env.get('APNS_KEY')
    const apnsKeyId = Deno.env.get('APNS_KEY_ID')
    const apnsTeamId = Deno.env.get('APNS_TEAM_ID')
    if (!apnsKey || !apnsKeyId || !apnsTeamId) {
      console.log(`notify-parent: would send ${sent} push(es) for ${body.student_id} (${body.status})`)
      return Response.json({ sent, delivered: 0, note: 'senders not configured' }, { status: 200 })
    }

    const { data: student } = await supabase
      .from('students')
      .select('full_name')
      .eq('id', body.student_id)
      .single()
    const name = student?.full_name ?? 'Your child'
    const alertBody = body.status === 'late'
      ? `${name} was marked late today.`
      : `${name} was marked absent today.`

    const jwt = await apnsJwt(apnsKey, apnsKeyId, apnsTeamId)
    const topic = Deno.env.get('APNS_TOPIC') ?? 'com.tava.TAVAttendance'
    const host = Deno.env.get('APNS_HOST') ?? 'https://api.push.apple.com'

    let delivered = 0
    const skipped: string[] = []
    for (const t of tokens ?? []) {
      if (t.platform !== 'ios') {
        skipped.push(`${t.platform}: sender not wired`)
        continue
      }
      const res = await fetch(`${host}/3/device/${t.token}`, {
        method: 'POST',
        headers: {
          authorization: `bearer ${jwt}`,
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
    }

    return Response.json({ sent, delivered, skipped }, { status: 200 })
  } catch (err) {
    return Response.json({ error: String(err) }, { status: 500 })
  }
})
