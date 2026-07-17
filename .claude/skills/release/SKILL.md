---
name: release
description: Use when preparing or shipping a new build of the TAVA mobile apps — Android to Firebase App Distribution, iOS to the GitHub release + AltStore source (altstore.json). Covers change collection, the required version-number prompt, version bumps, the exact commands, and the altstore.json update that AltStore installs from.
---

# TAVA App Release

Two independent channels. Run either or both. The web dashboard is NOT this
skill — that's the `deploy` skill.

| Channel | Tool | Consumer |
|---|---|---|
| Android | `Android/distribute.sh` → Firebase App Distribution | testers in `Android/testers.txt` get an email |
| iOS | `iOS/build-ipa.sh` → GitHub release asset + `web/public/altstore.json` | AltStore on the kiosk iPad (source URL `https://dash.thegoodcompanysg.dev/altstore.json`) |

## 0. Release intake — report, ask, then stop

Do this before editing version files, building, uploading, or deploying.

1. Read the current versions from their sources of truth:
   - Android: `versionName` and `versionCode` in `Android/app/build.gradle.kts`.
   - iOS: `CFBundleShortVersionString` and `CFBundleVersion` in `iOS/project.yml`.
2. Stop and report the mismatch if the Android and iOS marketing versions differ.
3. For display, normalise a two-component version such as `1.1` to `1.1.0`, but
   also show the exact stored value and each platform's build number.
4. Find the most recent release commit with
   `git log --format='%H' --grep='^release:' -n 1`. Treat it as the release
   baseline. If none exists, use the commit immediately before the first
   versioned release and state that fallback.
5. Build a concise change summary from all of these inputs:
   - `RELEASE_NOTES.md` → `Unreleased`;
   - commits after the baseline;
   - tracked working-tree changes against the baseline;
   - untracked files from `git status --short` that belong in the product.
   Inspect the diffs enough to describe behaviour, security, schema, and
   operational changes—not just filenames. Do not run `git stash`; the ledger
   is a release-notes staging area, not a Git stash.
6. Ask exactly one blocking question in this shape:

```text
Changes since the last build:
- <change>
- <change>

The current version number is 1.1.0 (stored as 1.1; Android build 3, iOS build 5).
What version number would you like to use?
```

Never infer the next marketing version. Wait for an explicit answer such as
`1.1.1`; do not make release mutations in the same turn as the question.

After the user replies, validate a numeric `MAJOR.MINOR.PATCH` value greater
than the current normalised version. Use that exact value on both platforms.
Increment Android `versionCode` and iOS `CFBundleVersion` independently by one.

## 1. Version bump (both platforms, keep in sync)

- **Android**: `Android/app/build.gradle.kts` → `versionCode` (+1 every release) and `versionName`.
- **iOS**: `iOS/project.yml` → `CFBundleShortVersionString` (marketing version) and `CFBundleVersion` (+1 every release). Never edit Info.plist/pbxproj directly — XcodeGen regenerates them.
- Update `Android/release-notes.txt` from the user-facing subset of the approved
  change summary (Firebase shows it to testers).

## 2. Android → Firebase App Distribution

Prereqs (already done once, 2026-07-12): `firebase login`, app registered.
The App ID `1:879371219921:android:dc7a8dbf4d8df141bf66f0` is baked into the
script as the default. Signing keystore + `KEYSTORE_*` values live in the
gitignored `Android/secrets.properties` (+ `Android/release.jks`).

```bash
cd Android && ./distribute.sh
```

That's it — builds `assembleRelease` (JDK 21 exported inside the script) and
uploads with notes from `release-notes.txt` to testers in `testers.txt`.
Success output ends with a Firebase console link. Failure modes: `firebase`
CLI not on PATH (`npm i -g firebase-tools`), expired login (`firebase login
--reauth`), missing keystore values.

## 3. iOS → GitHub release + AltStore

### 3a. Build the signed IPA

```bash
cd iOS && ./build-ipa.sh
```

Archives + exports to `iOS/export-builds/TAVAttendance.ipa` (gitignored) using
`ExportOptions.plist` (personal-team signing — installs expire after 7 days,
AltStore re-signs on refresh; that's expected). The script prints the IPA size
— **record it, altstore.json needs the exact byte count**.

### 3b. Upload to the GitHub release

The AltStore source points at the fixed asset URL of the `pre-release` tag, so
**clobber the asset on the same release** — do NOT create a new tag or the
download URL breaks:

```bash
gh release upload pre-release iOS/export-builds/TAVAttendance.ipa --clobber
```

(Repo: `thegoodcompany-sst/TAVAttendance`. Remember the global rule: check
`curl -s api.ipify.org` before git/gh network commands.)

### 3c. Update `web/public/altstore.json`

In the single entry under `apps[0].versions` (prepend a new object rather than
editing if you want history — AltStore uses the newest):

- `version` = CFBundleShortVersionString, `buildVersion` = CFBundleVersion
- `date` = today (YYYY-MM-DD)
- `size` = the exact byte count from step 3a (`stat -f %z iOS/export-builds/TAVAttendance.ipa`). **A wrong size makes AltStore fail the download.**
- `localizedDescription` = short human changelog
- `downloadURL` stays `https://github.com/thegoodcompany-sst/TAVAttendance/releases/download/pre-release/TAVAttendance.ipa`
- `minOSVersion` stays `17.0` unless the deployment target changed

### 3d. Ship the source

`altstore.json` is served by the web deployment (excluded from the auth gate
in `web/proxy.ts`), so the update is only live after a web deploy — run the
`deploy` skill (includes the mandatory schema gate). Verify:

```bash
curl -s https://dash.thegoodcompanysg.dev/altstore.json | python3 -c "import json,sys; v=json.load(sys.stdin)['apps'][0]['versions'][0]; print(v['version'], v['buildVersion'], v['size'])"
```

Then on the iPad: AltStore → Browse → TAVA source shows the new version;
update installs. (Human step — can't be automated.)

## 4. Wrap up

- After every requested channel has shipped and verification passes, move the
  bullets under `RELEASE_NOTES.md` → `Unreleased` into a dated
  `## VERSION — YYYY-MM-DD` section, then leave a fresh empty `Unreleased`
  section for subsequent work. Preserve old sections as release history.
- Commit the version bumps + altstore.json + release-notes.txt + release ledger.
- When the paid Apple Developer account lands, TestFlight replaces channel 3
  entirely — revisit this skill then.
