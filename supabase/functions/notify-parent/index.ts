// notify-parent — PROD-02 (parent push notifications)
//
// Sends a push to the parents of a student when their attendance is marked
// `late` or `absent`. Invoked by a DB trigger (via pg_net) on attendance_records,
// or callable directly with a JSON body. SHIPS DISABLED: it is a no-op unless the
// `push_notifications` feature flag is on, and requires APNs/FCM credentials that
// are provided out-of-band (see HUMANS.md).
//
// Deploy:  supabase functions deploy notify-parent
// Secrets: supabase secrets set FCM_SERVER_KEY=... APNS_KEY=... (see HUMANS.md)

import { createClient } from 'jsr:@supabase/supabase-js@2'

interface Payload {
  student_id: string
  status: 'present' | 'late' | 'absent' | 'excused'
  session_id?: string
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

    // TODO(HUMANS): wire real APNs (iOS) / FCM (Android/web) senders using the
    // secrets above. Left unimplemented intentionally — no credentials in repo.
    const sent = (tokens ?? []).length
    console.log(`notify-parent: would send ${sent} push(es) for ${body.student_id} (${body.status})`)

    return Response.json({ sent, delivered: 0, note: 'senders not yet wired' }, { status: 200 })
  } catch (err) {
    return Response.json({ error: String(err) }, { status: 500 })
  }
})
