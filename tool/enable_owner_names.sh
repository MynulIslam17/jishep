#!/usr/bin/env bash
# Publishes the recovered Rancho del Rey owner records to PRODUCTION and turns
# on cached owner-name display, on the project owner's explicit approval.
# (The former --licence requirement was removed by the project owner on
# 2026-11-23. No Melissa agreement reference is recorded or implied.)
#
#   tool/enable_owner_names.sh --approve=gps-para-el-cielo
#
# What it does, stopping at the first problem:
#   1. checks the snapshot checksum and the safety settings
#      (MELISSA_GLOBAL_DAILY_CREDITS=0, MELISSA_OWNER_DISCOVERY_ENABLED=false);
#   2. plan (read-only): refuses if any target document already exists;
#   3. apply (create-only) + verify: every document must match field by
#      field, otherwise the migration is rolled back;
#   4. sets MELISSA_ALLOW_OWNER_NAMES=true and MELISSA_OWNER_SHARED_CACHE=true
#      (nothing else) and deploys discoverOwners only;
#   5. checks the live function no longer refuses owner names.
# Paid discovery stays OFF: no Melissa request is possible (budget 0).
#
# Undo: set both flags back to false and deploy discoverOwners, then
#   (cd functions && node tool/migrate_pilot.js rollback --project=gps-para-el-cielo \
#      --in=../.local-backups/migration-20261122-165237 --approve=gps-para-el-cielo)
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT=gps-para-el-cielo
DIR=../.local-backups/migration-20261122-165237   # relative to functions/
ENV=functions/.env.$PROJECT
APPROVE=""
for a in "$@"; do
  case "$a" in
    --approve=*) APPROVE="${a#--approve=}" ;;
    *) echo "unknown argument: $a" >&2; exit 2 ;;
  esac
done
[ "$APPROVE" = "$PROJECT" ] || { echo "refused: --approve=$PROJECT is required" >&2; exit 2; }
unset FIRESTORE_EMULATOR_HOST

get() { grep -E "^$1=" "$ENV" | tail -1 | cut -d= -f2-; }
[ "$(get MELISSA_GLOBAL_DAILY_CREDITS)" = 0 ] || { echo "refused: MELISSA_GLOBAL_DAILY_CREDITS must be 0" >&2; exit 1; }
[ "$(get MELISSA_OWNER_DISCOVERY_ENABLED)" = false ] || { echo "refused: MELISSA_OWNER_DISCOVERY_ENABLED must be false" >&2; exit 1; }
[ "$(get MELISSA_GAP_FILL_ENABLED)" = false ] || { echo "refused: MELISSA_GAP_FILL_ENABLED must be false" >&2; exit 1; }

cd functions
echo "== 1/5 plan (read-only)"
PLAN=$(node tool/migrate_pilot.js plan --project=$PROJECT --in=$DIR)
echo "$PLAN"
node -e 'const p=JSON.parse(process.argv[1]); if (p.exists||p.conflicts.length||p.create<1) { console.error("refused: target not empty or nothing to create"); process.exit(1); }' "$PLAN"

echo "== 2/5 apply (create-only)"
node tool/migrate_pilot.js apply --project=$PROJECT --in=$DIR --approve=$PROJECT

echo "== 3/5 verify"
VERIFY=$(node tool/migrate_pilot.js verify --project=$PROJECT --in=$DIR)
if ! node -e 'const v=JSON.parse(process.argv[1]); process.exit(v.missing.length||v.different.length||v.notOurs.length ? 1 : 0)' "$VERIFY"; then
  echo "verify FAILED: rolling back" >&2
  node tool/migrate_pilot.js rollback --project=$PROJECT --in=$DIR --approve=$PROJECT
  exit 1
fi
echo "$VERIFY" | node -e 'const v=JSON.parse(require("fs").readFileSync(0,"utf8")); console.log(`identical: ${v.identical}`)'
cd ..

echo "== 4/5 owner names + shared cache ON (discovery stays OFF), deploy discoverOwners"
cp "$ENV" "$ENV.before-owner-names"
sed -i '' -e 's/^MELISSA_ALLOW_OWNER_NAMES=.*/MELISSA_ALLOW_OWNER_NAMES=true/' \
          -e 's/^MELISSA_OWNER_SHARED_CACHE=.*/MELISSA_OWNER_SHARED_CACHE=true/' "$ENV"
diff "$ENV.before-owner-names" "$ENV" || true
firebase deploy --only functions:discoverOwners --project $PROJECT --non-interactive

echo "== 5/5 live check (no sign-in: must now ask for sign-in, not refuse names)"
OUT=$(curl -s -X POST -H 'Content-Type: application/json' -d '{"data":{}}' \
  "https://us-central1-$PROJECT.cloudfunctions.net/discoverOwners")
echo "$OUT"
echo "$OUT" | grep -q sign_in_required || { echo "unexpected answer from discoverOwners" >&2; exit 1; }
echo "DONE. Build the apps with --dart-define=MELISSA_OWNERS=true."
