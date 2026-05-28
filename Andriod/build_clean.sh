#!/bin/bash
# Workaround for macOS duplicate " 2" build artifacts bug.
# Run this instead of ./gradlew assembleDebug when you see
# "mergeProjectDexDebug FAILED" with " 2.dex" files.
rm -rf app/build
./gradlew assembleDebug "$@"
