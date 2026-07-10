---
name: tava-build-and-env
description: Use when setting up TAVA Attendance from a fresh checkout or fresh machine, or when a BUILD fails (xcodebuild, xcodegen, gradle/JDK, npm, supabase CLI) — exact bootstrap commands per platform and the known environment traps (Xcode-beta DEVELOPER_DIR, CODE_SIGNING_ALLOWED, xcconfig // escaping, JDK 17/21 requirement, pinned Next.js).
---

# TAVA Build and Environment

From `git clone` to all three platforms building. Commands are verified
against this repo; traps are listed at the point you'd hit them.

**When NOT to use this skill:** the app builds but misbehaves (use
`tava-debugging-playbook`); running/deploying a built app (use
`tava-run-and-operate`).

## 0. Backend (shared, do this first)

```bash
# Requires the Supabase CLI (brew install supabase/tap/supabase)
supabase start          # local Postgres + Auth + Storage + Studio
supabase db reset       # applies migrations 001–016 in order + seed.sql
```

`db reset` also creates the two private Storage buckets (`result-slips`,
`student-photos`). Studio: http://127.0.0.1:54323.

**Trap:** local now has ALL migrations; prod does not (drift). Never reason
about prod from local behaviour — see `tava-prod-drift-campaign`.

## 1. iOS (`iOS/`)

```bash
cp iOS/Config.xcconfig.example iOS/Config.xcconfig
# Fill in SUPABASE_PROJECT_URL + SUPABASE_ANON_KEY.
# TRAP: xcconfig treats // as a comment — escape the URL as https:/$()/...
# or the value truncates to "https:" and the app can't reach Supabase.
```

The project is **XcodeGen-managed**: `iOS/project.yml` is the source of
truth; never hand-edit `TAVAttendance.xcodeproj`. If the .xcodeproj is stale
or missing: `cd iOS && xcodegen generate` (brew install xcodegen).

Build/test from CLI **on this dev machine** (2026-07-09: requires Xcode-beta):

```bash
cd iOS
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild test -project TAVAttendance.xcodeproj -scheme TAVAttendance \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```

**Traps:**
- `CODE_SIGNING_ALLOWED=NO` is mandatory here — a failure at `CodeSign swift-crypto_Crypto.bundle` is a pre-existing local keychain issue, NOT a code problem. Do not attempt to fix it.
- Scheme name comes from `project.yml`. Target: iPadOS 17+; the app is iPad-first.
- On a machine with a normal stable Xcode, drop the `DEVELOPER_DIR` override.
- Fresh-checkout credential wiring into `Info.plist` has an open human decision (HUMANS.md §13) — if the app builds but has empty credentials, that's why.

## 2. Android (`Android/`)

```bash
cp Android/secrets.properties.example Android/secrets.properties   # fill in values
cd Android
./gradlew clean compileDebugKotlin      # the accepted local verification
```

**Traps:**
- **JDK 17 or 21 required** for full builds/tests (AGP's jlink step). This dev machine has only JDK 26 → `./gradlew test` and `assembleDebug` fail with a jlink error (HUMANS.md §34). Fix: `brew install --cask temurin@21`, point `JAVA_HOME` at it. Until then, `compileDebugKotlin` is the verification bar (CI runs `assembleDebug` on JDK 17 and covers the rest).
- Release builds are R8-minified; Supabase/kotlinx-serialization keep rules live in `app/proguard-rules.pro` — test release builds after dependency bumps.
- One unit test exists (`DayAwareKioskTest`) — run it once JDK is fixed: `./gradlew testDebugUnitTest`.

## 3. Web (`web/`)

```bash
cp web/.env.local.example web/.env.local   # NEXT_PUBLIC_SUPABASE_URL / _ANON_KEY
cd web && npm install
npm run dev      # local dev
npm run lint && npm run build   # the verification bar
```

**Trap:** the repo pins a **non-standard Next.js (16.x)** — APIs and
conventions may differ from your training data. Read `web/AGENTS.md` and the
guides in `node_modules/next/dist/docs/` before writing Next-specific code.
React 19, Tailwind 4, Base UI + shadcn.

## 4. Repo hygiene (once per clone)

```bash
git config core.hooksPath .githooks   # secret-scanning pre-commit (DEVOPS-03)
```

macOS trap: Finder-duplicate files (`Name 2.swift`, `Dir 2/`) are junk —
delete them; never review, fix, or commit them.

## CI parity

`.github/workflows/ci.yml`: web lint+build (Node 20, placeholder env),
Android `assembleDebug` (temurin JDK 17, generated placeholder
secrets.properties), non-blocking `supabase db lint`. iOS is NOT in CI —
local build is the only iOS gate.

## Provenance and maintenance

Current as of 2026-07-09.
- Machine-specific facts (Xcode-beta path, JDK 26) are about the current dev Mac — re-check on any other machine: `xcode-select -p`, `/usr/libexec/java_home -V`.
- Web deps: `head -30 web/package.json`
- CI still matches: `cat .github/workflows/ci.yml`
