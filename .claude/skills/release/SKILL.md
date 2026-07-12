---
name: release
description: Use when shipping a new build of the TAVA mobile apps — Android to Firebase App Distribution, iOS to the GitHub release + AltStore source (altstore.json). Covers version bumps, the exact commands, and the altstore.json update that AltStore installs from.
---

# TAVA App Release

Two independent channels. Run either or both. The web dashboard is NOT this
skill — that's the `deploy` skill.

| Channel | Tool | Consumer |
|---|---|---|
| Android | `Android/distribute.sh` → Firebase App Distribution | testers in `Android/testers.txt` get an email |
| iOS | `iOS/build-ipa.sh` → GitHub release asset + `web/public/altstore.json` | AltStore on the kiosk iPad (source URL `https://dash.thegoodcompanysg.dev/altstore.json`) |

## 0. Version bump (both platforms, keep in sync)

- **Android**: `Android/app/build.gradle.kts` → `versionCode` (+1 every release) and `versionName`.
- **iOS**: `iOS/project.yml` → `CFBundleShortVersionString` (marketing version) and `CFBundleVersion` (+1 every release). Never edit Info.plist/pbxproj directly — XcodeGen regenerates them.
- Update `Android/release-notes.txt` with what changed (Firebase shows it to testers).

## 1. Android → Firebase App Distribution

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

## 2. iOS → GitHub release + AltStore

### 2a. Build the signed IPA

```bash
cd iOS && ./build-ipa.sh
```

Archives + exports to `iOS/export-builds/TAVAttendance.ipa` (gitignored) using
`ExportOptions.plist` (personal-team signing — installs expire after 7 days,
AltStore re-signs on refresh; that's expected). The script prints the IPA size
— **record it, altstore.json needs the exact byte count**.

### 2b. Upload to the GitHub release

The AltStore source points at the fixed asset URL of the `pre-release` tag, so
**clobber the asset on the same release** — do NOT create a new tag or the
download URL breaks:

```bash
gh release upload pre-release iOS/export-builds/TAVAttendance.ipa --clobber
```

(Repo: `thegoodcompany-sst/TAVAttendance`. Remember the global rule: check
`curl -s api.ipify.org` before git/gh network commands.)

### 2c. Update `web/public/altstore.json`

In the single entry under `apps[0].versions` (prepend a new object rather than
editing if you want history — AltStore uses the newest):

- `version` = CFBundleShortVersionString, `buildVersion` = CFBundleVersion
- `date` = today (YYYY-MM-DD)
- `size` = the exact byte count from step 2a (`stat -f %z iOS/export-builds/TAVAttendance.ipa`). **A wrong size makes AltStore fail the download.**
- `localizedDescription` = short human changelog
- `downloadURL` stays `https://github.com/thegoodcompany-sst/TAVAttendance/releases/download/pre-release/TAVAttendance.ipa`
- `minOSVersion` stays `17.0` unless the deployment target changed

### 2d. Ship the source

`altstore.json` is served by the web deployment (excluded from the auth gate
in `web/proxy.ts`), so the update is only live after a web deploy — run the
`deploy` skill (includes the mandatory schema gate). Verify:

```bash
curl -s https://dash.thegoodcompanysg.dev/altstore.json | python3 -c "import json,sys; v=json.load(sys.stdin)['apps'][0]['versions'][0]; print(v['version'], v['buildVersion'], v['size'])"
```

Then on the iPad: AltStore → Browse → TAVA source shows the new version;
update installs. (Human step — can't be automated.)

## 3. Wrap up

- Commit the version bumps + altstore.json (+ release-notes.txt).
- When the paid Apple Developer account lands, TestFlight replaces channel 2
  entirely — revisit this skill then.
