<!-- BEGIN:nextjs-agent-rules -->
# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` before writing any code. Heed deprecation notices.
<!-- END:nextjs-agent-rules -->

The root `AGENTS.md` also applies here.

## Web change guide

- Use Bun and `bun.lock`; do not create npm or Yarn lockfiles.
- Keep Supabase reads in `lib/queries/*` and mutations in server actions. Client
  components must not become a second data-access layer.
- Query failures throw. Surface them through an error boundary or explicit
  state; do not turn a failed request into a misleading empty result.
- Keep admin/superadmin checks server-side and enforce the same boundary in RLS
  or a self-guarding RPC. Hidden UI is not authorization.
- Every reporting, export, award, analytics, and parent query excludes Study
  Space at its source.
- Add Vitest coverage for security-sensitive pure helpers, response shaping,
  aggregation, and export filtering.

Run from this directory:

```bash
bun install --frozen-lockfile
bun audit --audit-level=high
bun run test
bun run lint
bun run build
```

Use the `deploy` runbook before a production deployment.
