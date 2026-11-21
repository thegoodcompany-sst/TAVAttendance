# Convex teacher-prompts backend

The new-year teacher workflow lives in `backend/convex`. Convex Auth owns credentials and sessions. A separate staff profile holds an immutable public UUID, role, active status and link to the Auth user. Only authenticated public functions shape student data. Internal functions own staff provisioning, calendar imports, policy settings and the queue. The native API and standard Convex API call the same domain functions. [Client contract](CONVEX_API.md)

## Running the backend

From `backend/` on Node 24, run `npm ci`, `npm run typecheck` and `npx vitest run`. Tests use an in-memory Convex database and fake transports. Generated bindings are tracked. For the configured developer checkout use `npx convex dev --once`. Fresh deployments need their own auth key pair and `npx convex run settings:initialize`. Initialization is idempotent and creates both flags OFF, the default timing policy and demo mode OFF.

The pinned Auth package is the maintained v1 Password-provider line (0.0.98). It implements the requested native sign-in/refresh protocol and accepts a deployer-managed signing key. A move to Auth v2 needs an identity and session migration. [Convex Auth versions](https://docs.convex.dev/auth/convex-auth) · [Password provider](https://labs.convex.dev/auth/config/passwords)

## Provisioning and calendar

1. Generate a random 32-byte activation secret in a password manager. Hash the precise UTF-8 secret with SHA-256 and encode the digest as 64 lowercase hex digits. Call internal `staff:provision` with `{email,name,role,invitationHash}`. Give only the intended staff member the secret through a private channel. They activate once, then use email and password. Unused invitations expire after 24 hours. `staff:renewInvitation` replaces the digest for an unactivated account. Account recovery for an already activated password requires a separate operator recovery workflow.
2. `calendar:addTerm`, `addClass`, `addStudent` and `enroll` create the catalog. Their results are Convex document IDs for subsequent internal operations. `calendar:setRule` accepts `{class,term,teacher,weekday,start,minutes,from,until,active}` and an optional existing rule `id`. Use the teacher's profile document ID here. ISO weekday runs Monday 1 to Sunday 7. A rule must fit the term. A student can have successive inclusive enrolment periods. `calendar:addClosure` takes `{from,until,reason,class?}`. Omitting class applies centre-wide. Reasons are `public_holiday` and `centre_closed`.
3. Run `calendar:generate_lessons` after calendar changes with `{from,until}` covering affected dates. A daily cron at 00:05 Singapore generates today through today+42. Indexed rule/date reads and writes in the same transaction preserve occurrence identity. Before work starts, regeneration can update schedules and roster snapshots. Rescheduling preserves the original occurrence and checks closures and enrolment against the new local date. Replacing a teacher transfers authority and pending plans together. `staff:setAccess` rejects loss of the teacher role while active rules or open lessons depend on that teacher.
4. The teacher list includes assigned accountable work, a seven-day backlog and today's completed/cancelled cards. Admins can inspect a 92-day backlog and missing submissions. Study Space is omitted at the domain boundary. Attendance uses both register revision and per-row observed time. One immutable submission records the final register and feedback revisions.

## Planning and dispatch

Each lesson has four logical plan rows. The default offsets from end are −5, 0, +15 and +60 minutes. Plans are deferred across Singapore quiet hours to 09:00, spaced by at least five minutes. Overdue is derived from the final planned time plus fifteen minutes. For a 21:00 finish this means 09:15 the next day. Admin can see unfinished lessons from scheduled end. Snooze postpones pending stages by up to three ten-minute requests. Internal `settings:updatePolicy` validates offsets, grace and the snooze limit, then replans open lessons atomically.

A minute cron snapshots up to five recent active devices per due stage. Normal dispatch latency is up to one tick plus scheduling latency. It skips obsolete stages after a delay. Missing devices produce one terminal outcome. An indexed plan/device lookup and Convex transaction conflict detection prevent duplicate fan-out. A claim schedules the Node action in the same transaction. Its prepare mutation rechecks the lease, assignment, revision, device, flags, time and completion. Only prepare can move a claim into sending.

The APNs action uses HTTP/2, an allowlisted payload and a stable request/collapse ID. An acknowledgement can transition only its own lease. A 429 or 5xx retries after one then five minutes, with at most three attempts. A 410 or BadDeviceToken revokes only the prepared version. When a worker dies before prepare, another tick can recover the claim. If a request might already have reached Apple, the outcome is recorded as unknown and that attempt is terminal. This trades a possible missed push for protection against duplicate transmission. A request already in flight can still arrive after substitution or submission. Acceptance proves neither receipt by the phone nor teacher review. The teacher list and admin follow-up remain available.

## Deployment settings

| Name | Use |
|---|---|
| `CONVEX_DEPLOYMENT` | Local CLI deployment selection, held in ignored configuration |
| `CONVEX_DEPLOY_KEY` | Scoped operator/CI deployment credential for a separately approved release |
| `CONVEX_SITE_URL` | Deployment-provided issuer and auth discovery base |
| `JWT_PRIVATE_KEY`, `JWKS`, `SITE_URL` | Deployment-specific signing key, public key set and configured site origin |
| `APNS_DRY_RUN` | Defaults to true. Only the exact value `false` enables real transport. Tagged demo lessons always use dry-run. |
| `APNS_ENV` | `sandbox` or `production`, matching the device registration in real mode |
| `APNS_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID` | Private .p8 PEM contents or base64 of the PEM, Apple key ID and developer team ID |
| `APNS_BUNDLE_ID` | APNs topic, default `com.tava.TAVAttendance` |

`teacher_prompts` gates all lesson APIs and dispatch. `teacher_prompt_push` is additionally required for live APNs. `settings:setFlag` is internal. Keep `AUTH_LOG_SECRETS` unset. Device tokens are private. Delivery logs contain normalized outcomes, attempt numbers and provider IDs. Mutation receipts store a request digest and bounded receipt. Feedback and child names belong only in authorized application records.

On the designated dev deployment, initial key generation is `node scripts/auth-keys.mjs adept-duck-658 https://adept-duck-658.convex.site`. The script supplies fresh RSA keys to the CLI over stdin and refuses conflicting existing configuration. Production uses a different key pair. [Cutover procedure](cutover.md)

## Dev fixture

On an approved development deployment enable `settings:setDemoEnabled {"enabled":true}`. Run `npx convex run seed:demo '{"email":"teacher@example.invalid","minutes":6}'` with the provisioned teacher's email. Repeat calls return the existing tag and lesson UUID. The master flag controls visibility. To restart, pass that tag to `npx convex run seed:wipeDemo '{"tag":"<returned UUID>"}'`, then seed again. All invented class, student, enrollment, lesson, work and delivery records carry this tag. The teacher's profile, account and own device registrations survive the wipe. Restore the demo setting and rollout flags after the exercise.

## Next.js prototype

The prototype selects an invented staff UUID using the `tp_identity` cookie.
Its server-side `lib/rpc.ts` executes SQL under that demo identity, and its
preview guard verifies a marker in the assigned PostgreSQL database.

A connected mode selected by `NEXT_PUBLIC_CONVEX_URL` needs a Password sign-in
and sign-out flow, per-user server-side session storage with serialized refresh,
and a profile/role lookup for page access. The RPC adapter can then POST the
allowlisted teacher and calendar functions to the cloud query/mutation endpoints
with that session’s bearer. Keep the database-marker checks, demo identity selector
and `simulate_prompt_now` in local demo mode. Verify a teacher cannot access a
different teacher’s lesson, including after account switching or token refresh.
[Native request shapes](CONVEX_API.md)

## Free-plan operations

One minute tick uses about 43,200 scheduled calls per 30-day month per active deployment, before actual lesson work, client queries or other crons. Each attempted device delivery also uses action, prepare and finish calls. Check function calls, database I/O/storage and action compute in the dashboard. Preview/dev deployments also consume team resources. Calendar generation accepts at most 92 days at once. Use smaller date ranges for larger imports and monitor transaction limits as roster sizes grow. Agree delivery retention and recovery/export ownership before real student records are loaded. [Convex resource limits](https://docs.convex.dev/production/state/limits)

## Apple setup

Enable Push Notifications for the app's explicit App ID. The mobile release owner enables the matching capability and provisioning profile for the installed build. Create an APNs token-signing key for the intended team, topic and environment. Store its .p8, key ID and team ID in deployment secrets. Device tokens must come from the matching APNs environment. A physical phone pilot must verify permission, receipt, deep link, account switch and opt-out. [Apple APNs token setup](https://developer.apple.com/help/account/capabilities/communicate-with-apns-using-authentication-tokens/)

Sign in with Apple is a later provider. Enable it on the primary App ID. Create and associate a Services ID, register the deployment's HTTP Actions domain and the exact HTTPS return URL `https://<deployment>.convex.site/api/auth/callback/apple`. Create a separate Apple sign-in key and generate the expiring client-secret JWT. Configure `AUTH_APPLE_ID` and `AUTH_APPLE_SECRET`, add the Apple provider to `auth.ts`, and extend the account-link callback with verified, staff-approved linking. An Apple relay email or client-supplied role cannot grant staff access. Plan client-secret renewal and test account linking before enabling the provider. [Convex Auth Apple setup](https://labs.convex.dev/auth/config/oauth/apple)
