---
name: release
description: Use when preparing or shipping TAVA mobile builds — version intake, Android Firebase App Distribution, iOS TestFlight/App Store Connect, verification, and release-ledger updates.
---

# TAVA mobile release

| Channel | Current path | Consumer |
|---|---|---|
| Android | `Android/distribute.sh` → Firebase App Distribution | approved testers |
| iOS | signed archive + `ExportOptionsTestFlight.plist` → App Store Connect/TestFlight | beta/review users |

The web dashboard has a separate `deploy` runbook.

## 0. Intake: report, ask, stop

Before modifying a version or uploading:

1. Read Android `versionName`/`versionCode` from
   `Android/app/build.gradle.kts` and iOS
   `CFBundleShortVersionString`/`CFBundleVersion` from `iOS/project.yml`.
2. Stop on a marketing-version mismatch.
3. Find the last `release:` commit and summarize `RELEASE_NOTES.md` Unreleased,
   commits, tracked changes and product-relevant untracked files since it.
4. Ask one blocking question for the new numeric `MAJOR.MINOR.PATCH` version.
   Never infer it.

After approval, use the exact marketing version on both platforms. Increment
Android `versionCode` and iOS `CFBundleVersion` independently by one. Update
`Android/release-notes.txt` with the user-facing subset.

## 1. Security and build gates

- Release only a reviewed commit; record its hash.
- Run the CI-equivalent checks in `tava-validation-and-qa`.
- Confirm migrations required by the clients are live with the production
  drift/security gates before distributing them.
- Run current-tree secret scanning and dependency audits.
- Keep release keystores, provisioning profiles, API keys, App Review
  credentials and database URLs out of Git, terminal arguments, logs and
  release notes.

## 2. Android → Firebase App Distribution

Prerequisites: authenticated Firebase CLI, `Android/release.jks`, and
`KEYSTORE_FILE`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` in the
gitignored `Android/secrets.properties`.

```bash
cd Android
./distribute.sh
```

The script uses the registered Firebase App ID by default, builds the signed
R8-minified release APK, and uploads using `release-notes.txt` and
`testers.txt`. Verify the Firebase release identifies the expected
`versionName`, `versionCode`, signing identity and source commit. Back up the
keystore separately; losing it prevents updates under the same identity.

## 3. iOS → TestFlight/App Store Connect

The source of truth is `iOS/project.yml`. It currently selects the distribution
profile for Release builds; `ExportOptionsTestFlight.plist` is the App Store
Connect export configuration. Regenerate before archiving:

```bash
cd iOS
xcodegen generate
xcodebuild archive \
  -project TAVAttendance.xcodeproj \
  -scheme TAVAttendance \
  -destination 'generic/platform=iOS' \
  -archivePath export-builds/TAVAttendance.xcarchive
xcodebuild -exportArchive \
  -archivePath export-builds/TAVAttendance.xcarchive \
  -exportOptionsPlist ExportOptionsTestFlight.plist \
  -exportPath export-builds/testflight
```

Use the authenticated App Store Connect upload mechanism installed on the
release Mac. Check its local help before upload rather than copying a stale CLI
syntax from this runbook. Verify the processed build in App Store Connect:
bundle `com.tava.TAVAttendance`, app ID `6790169580`, expected marketing/build
versions, compliance metadata, beta-review state and source commit.

Run `asc validate --app 6790169580 --version 1.0` only for the existing 1.0 App
Store submission record. App Review credentials belong only in App Store
Connect and the team password manager. HUMANS.md §66 requires rotation of the
former exposed review account before release.

## 4. Close the release

- Verify install/launch/sign-in on each requested channel without real student
  data in screenshots or logs.
- Move Unreleased bullets into `## VERSION — YYYY-MM-DD`; preserve history and
  leave an empty Unreleased section.
- Commit version files, regenerated Xcode project and release notes.
- Record immutable external build/release identifiers in the handoff.

## Provenance

Audited 2026-07-26 against the 1.1.1 version sources,
`Android/distribute.sh`, `iOS/ExportOptionsTestFlight.plist`, and the App Store
Connect notes in `CLAUDE.md`.
