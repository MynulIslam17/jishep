#!/usr/bin/env bash
# Production rollout of the 2026-11-24 blueprint changes (backend only).
# PREPARED, NOT RUN: the project owner chose "local only" on 2026-11-24.
# Run it only after explicit approval:
#
#   tool/deploy_blueprint.sh --approve=gps-para-el-cielo
#
# Order (stops at the first problem):
#   0. safety checks: paid discovery OFF, app-wide budget 0, gap-fill OFF,
#      MELISSA_CACHE_DAYS=365, verified + location gates ON, App Check soft
#      gate ON (hard enforcement OFF for old app builds), gcloud ADC
#      present (needed by the Admin-SDK tools), project is not cielo-63925.
#   1. backups → .local-backups/prod-blueprint-<ts>/: the currently released
#      Firestore ruleset name, the deployed functions list, and the TTL
#      backup of the shared Melissa cache (old expiresAt + updateTime).
#   2. firebase deploy --dry-run (functions, rules, indexes).
#   3. Firestore rules + indexes (location lock, primary_locations,
#      location_corrections, audit index).
#   4. Cloud Functions (discoverOwners with server-side location, verified
#      gate, kill switch; 365-day cache default; cleanup fix).
#   5. 365-day TTL migration of the shared cache: apply + verify.
#   6. live check: unauthenticated discoverOwners must answer
#      sign_in_required (function up, auth enforced).
#
# No Melissa request is possible at any step (budget 0, discovery OFF).
# The mobile apps need no change for this rollout; the new app build's
# location-setup write falls back automatically if the old rules are live.
#
# ROLLBACK (each independent):
#   rules:     firebase deploy --only firestore:rules from the previous commit,
#              or re-release the saved ruleset name (backups/ruleset.txt) in
#              the Firebase console › Firestore › Rules › history.
#   functions: git checkout <previous commit> -- functions && firebase deploy --only functions
#   TTL:       (cd functions && node tool/migrate_cache_ttl.js rollback \
#                --project=gps-para-el-cielo --in=<backup.json> --approve=gps-para-el-cielo)
#   paid stop: (cd functions && node tool/melissa_ops.js kill --project=gps-para-el-cielo \
#                --reason="..." --approve=gps-para-el-cielo)
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT=gps-para-el-cielo
ENV=functions/.env.$PROJECT
APPROVE=""
for a in "$@"; do
  case "$a" in
    --approve=*) APPROVE="${a#--approve=}" ;;
    *) echo "unknown argument: $a" >&2; exit 2 ;;
  esac
done
[ "$APPROVE" = "$PROJECT" ] || { echo "refused: --approve=$PROJECT is required" >&2; exit 2; }
[ "$PROJECT" != "cielo-63925" ] || exit 2
unset FIRESTORE_EMULATOR_HOST

get() { grep -E "^$1=" "$ENV" | tail -1 | cut -d= -f2-; }
need() { [ "$(get "$1")" = "$2" ] || { echo "refused: $1 must be $2 in $ENV" >&2; exit 1; }; }
echo "== 0/6 safety checks"
need MELISSA_GLOBAL_DAILY_CREDITS 0
need MELISSA_OWNER_DISCOVERY_ENABLED false
need MELISSA_GAP_FILL_ENABLED false
need MELISSA_CACHE_DAYS 365
need MELISSA_OWNER_REQUIRE_VERIFIED true
need MELISSA_REQUIRE_APP_CHECK true
need ENFORCE_APP_CHECK false
gcloud auth application-default print-access-token >/dev/null 2>&1 || {
  echo "refused: run 'gcloud auth application-default login' first (Admin-SDK tools)" >&2; exit 1; }

TS=$(date +%Y%m%d-%H%M%S)
BK=.local-backups/prod-blueprint-$TS
mkdir -p "$BK"; chmod 700 "$BK"
echo "== 1/6 backups → $BK"
TOKEN=$(gcloud auth print-access-token)
curl -s -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $PROJECT" \
  "https://firebaserules.googleapis.com/v1/projects/$PROJECT/releases" > "$BK/rules_releases.json"
node -e 'const r=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); const f=(r.releases||[]).find(x=>x.name.endsWith("/cloud.firestore")); if(!f){console.error("no firestore release found");process.exit(1)} console.log(f.rulesetName)' "$BK/rules_releases.json" > "$BK/ruleset.txt"
echo "  current ruleset: $(cat "$BK/ruleset.txt")"
firebase functions:list --project $PROJECT > "$BK/functions_list.txt" 2>&1 || true
(cd functions && node tool/migrate_cache_ttl.js backup --project=$PROJECT --out="../$BK")
TTL_BACKUP=$(ls -t "$BK"/ttl-backup-*.json | head -1)
echo "  TTL backup: $TTL_BACKUP"

echo "== 2/6 dry run"
firebase deploy --only functions,firestore:rules,firestore:indexes --project $PROJECT --dry-run --non-interactive

echo "== 3/6 Firestore rules + indexes"
firebase deploy --only firestore:rules,firestore:indexes --project $PROJECT --non-interactive

echo "== 4/6 Cloud Functions"
firebase deploy --only functions --project $PROJECT --non-interactive

echo "== 5/6 365-day TTL migration (shared cache)"
(cd functions && node tool/migrate_cache_ttl.js apply --project=$PROJECT --in="../$TTL_BACKUP" --approve=$PROJECT)
# Expiry extended AND every backed-up document still present with an
# identical fingerprint (the 53 production records: 50 named, 2 not found,
# 1 scan on 2026-11-24).
(cd functions && node tool/migrate_cache_ttl.js verify --project=$PROJECT --in="../$TTL_BACKUP") || {
  echo "TTL verify FAILED — roll back with the command in the header" >&2; exit 1; }

echo "== 6/6 live check"
OUT=$(curl -s -X POST -H 'Content-Type: application/json' -d '{"data":{}}' \
  "https://us-central1-$PROJECT.cloudfunctions.net/discoverOwners")
echo "$OUT"
echo "$OUT" | grep -q sign_in_required || { echo "unexpected answer from discoverOwners" >&2; exit 1; }
(cd functions && node tool/melissa_ops.js status --project=$PROJECT)
echo "DONE. Record the deployed commit in docs/PRODUCTION_DEPLOYMENT.md (release log)."
