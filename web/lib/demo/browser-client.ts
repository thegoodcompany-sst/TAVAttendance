/* eslint-disable @typescript-eslint/no-explicit-any */
/**
 * Browser-side Supabase stand-in for demo mode. The demo's data lives behind
 * server actions (lib/demo/state.ts), so the browser only needs harmless
 * answers for the few client-side calls the app makes (analytics, sign-out,
 * uploads). It never opens a network connection.
 */
const unavailable = { message: 'Not available in demo mode.' }

function query(): any {
  const result = { data: null, error: unavailable, count: null, status: 400, statusText: 'Demo' }
  const builder: any = new Proxy({}, {
    get(_target, prop) {
      if (prop === 'then') return (resolve: any, reject: any) => Promise.resolve(result).then(resolve, reject)
      return () => builder
    },
  })
  return builder
}

export function createDemoBrowserClient() {
  return {
    __demo: true as const,
    from: () => query(),
    rpc: (fn: string) => (fn === 'submit_app_events'
      ? Promise.resolve({ data: 0, error: null })
      : query()),
    auth: {
      getUser: async () => ({ data: { user: null }, error: null }),
      getSession: async () => ({ data: { session: null }, error: null }),
      signInWithPassword: async () => ({ data: { user: null, session: null }, error: unavailable }),
      signOut: async () => ({ error: null }),
      setSession: async () => ({ data: { user: null, session: null }, error: unavailable }),
      updateUser: async () => ({ data: { user: null }, error: unavailable }),
      verifyOtp: async () => ({ data: { user: null, session: null }, error: unavailable }),
      exchangeCodeForSession: async () => ({ data: { user: null, session: null }, error: unavailable }),
      onAuthStateChange: () => ({ data: { subscription: { unsubscribe: () => {} } } }),
    },
    storage: {
      from: () => ({
        upload: async () => ({ data: null, error: { message: 'File uploads are switched off in demo mode.' } }),
        uploadToSignedUrl: async () => ({ data: null, error: { message: 'File uploads are switched off in demo mode.' } }),
      }),
    },
  }
}
