#!/usr/bin/env bash
# Build + upload the release APK to Firebase App Distribution.
# Prereqs (one-time): firebase login, and an Android app registered in a
# Firebase project. Put its App ID (Project settings > your apps) below or pass as $1.
set -euo pipefail
cd "$(dirname "$0")"

APP_ID="${1:-${FIREBASE_APP_ID:-1:879371219921:android:dc7a8dbf4d8df141bf66f0}}"
if [ -z "$APP_ID" ]; then
  echo "Usage: ./distribute.sh <firebase-app-id>   (or set FIREBASE_APP_ID)" >&2
  exit 1
fi

export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home
./gradlew assembleRelease

firebase appdistribution:distribute \
  app/build/outputs/apk/release/app-release.apk \
  --app "$APP_ID" \
  --release-notes-file release-notes.txt \
  --testers-file testers.txt
