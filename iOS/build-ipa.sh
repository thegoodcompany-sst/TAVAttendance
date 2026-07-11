#!/bin/bash
# Archive + export a signed .ipa for AltStore, into iOS/export-builds/ (gitignored).
set -euo pipefail
cd "$(dirname "$0")"

export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
OUT=export-builds
ARCHIVE="$OUT/TAVAttendance.xcarchive"

xcodegen generate

xcodebuild archive \
  -project TAVAttendance.xcodeproj \
  -scheme TAVAttendance \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath "$OUT"

echo "IPA:  $OUT/TAVAttendance.ipa"
stat -f 'size: %z bytes' "$OUT/TAVAttendance.ipa"
