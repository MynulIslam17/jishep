#!/usr/bin/env bash
# Local emulators (auth, firestore, functions) for project gps-para-el-cielo.
# Data lives in .emulator-data/ (git-ignored; holds real pilot owner data):
# imported at start, exported on a clean exit AND every 10 minutes, so an
# emulator restart, crash or reboot no longer loses the pilot cache.
# Melissa: replay-only (functions/src/guard.js); nothing can be billed.
set -euo pipefail
cd "$(dirname "$0")/.."
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home}"
export PATH="$JAVA_HOME/bin:$PATH"
unset MELISSA_EMULATOR_LIVE
mkdir -p .emulator-data
( while sleep 600; do
    firebase emulators:export .emulator-data --project gps-para-el-cielo --config firebase.lan.json --force >/dev/null 2>&1 || true
  done ) &
SAVER=$!
trap 'kill $SAVER 2>/dev/null || true' EXIT
firebase emulators:start --only auth,functions,firestore --project gps-para-el-cielo \
  --config firebase.lan.json --import .emulator-data --export-on-exit .emulator-data
