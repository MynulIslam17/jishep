#!/usr/bin/env bash
# READ-ONLY security preflight before real Melissa owner lookups are turned
# on in production. Changes nothing, calls no Melissa API, spends nothing.
# Every line must say PASS before tool/activate_paid.sh may be run.
#
#   tool/preflight_paid.sh [--min-verified=20] [--min-share=0.9]
#
# Checks:
#   1 deployed discoverOwners config: App Check soft gate, verified-account
#     gate, 250 m location gate, 365-day cache, shared cache, kill switch
#     code present (deployed after 2026-11-24)
#   2 live Firestore rules == firestore.rules in this checkout
#   3+4 App Check proven by real traffic (Cloud Logging, last 7 days):
#     verified calls from iOS AND Android, at least --min-verified in all,
#     share >= --min-share
#   5 kill switch not set; no out-of-credits pause
#   6 365-day migration verified (all 53 records fresh, needs ADC)
set -uo pipefail
cd "$(dirname "$0")/.."
PROJECT=gps-para-el-cielo
MIN_VERIFIED=20
MIN_SHARE=0.9
for a in "$@"; do
  case "$a" in
    --min-verified=*) MIN_VERIFIED="${a#*=}" ;;
    --min-share=*) MIN_SHARE="${a#*=}" ;;
    *) echo "unknown argument: $a" >&2; exit 2 ;;
  esac
done
unset FIRESTORE_EMULATOR_HOST
FAIL=0
pass() { echo "PASS  $*"; }
fail() { echo "FAIL  $*"; FAIL=1; }
TOKEN=$(gcloud auth print-access-token)
H=(-H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $PROJECT")

echo "== 1 deployed discoverOwners configuration"
ENVJSON=$(gcloud functions describe discoverOwners --gen2 --region=us-central1 --project=$PROJECT \
  --format="json(serviceConfig.environmentVariables)" 2>/dev/null)
envv() { python3 -c 'import json,sys; print(json.loads(sys.argv[1])["serviceConfig"]["environmentVariables"].get(sys.argv[2],""))' "$ENVJSON" "$1"; }
want() { local v; v=$(envv "$1"); [ "$v" = "$2" ] && pass "$1=$v" || fail "$1=${v:-<unset>} (want $2)"; }
want MELISSA_REQUIRE_APP_CHECK true
want MELISSA_OWNER_REQUIRE_VERIFIED true
want MELISSA_OWNER_LOCATION_TOLERANCE_M 250
want MELISSA_CACHE_DAYS 365
want MELISSA_OWNER_NEGATIVE_CACHE_DAYS 365
want MELISSA_OWNER_SHARED_CACHE true
want MELISSA_ALLOW_OWNER_NAMES true

echo "== 2 live Firestore rules"
LIVE=$(curl -s "${H[@]}" "https://firebaserules.googleapis.com/v1/projects/$PROJECT/releases" \
  | python3 -c 'import json,sys; r=json.load(sys.stdin); print([x for x in r["releases"] if x["name"].endswith("/cloud.firestore")][0]["rulesetName"])')
curl -s "${H[@]}" "https://firebaserules.googleapis.com/v1/$LIVE" \
  | python3 -c 'import json,sys; sys.stdout.write(json.load(sys.stdin)["source"]["files"][0]["content"])' > /tmp/preflight_rules.$$
if diff -q /tmp/preflight_rules.$$ firestore.rules >/dev/null; then pass "live rules == firestore.rules ($LIVE)"
else fail "live rules differ from firestore.rules (deploy the blueprint first)"; fi
rm -f /tmp/preflight_rules.$$

echo "== 3+4 App Check: registered and working on real traffic (7 days)"
echo "   thresholds: --min-verified=$MIN_VERIFIED --min-share=$MIN_SHARE"
# The App Check API returns default settings for unregistered apps too, so
# registration is proven by tokens the backend accepted, per platform.
gcloud services list --enabled --project=$PROJECT --format="value(config.name)" | grep -qx playintegrity.googleapis.com \
  && pass "Play Integrity API enabled (Android registration done)" || fail "Play Integrity API not enabled (register Android in App Check)"
LOGS=$(gcloud logging read 'jsonPayload.event="app_check" AND jsonPayload.fn="discoverOwners"' \
  --project=$PROJECT --freshness=7d --limit=5000 --format="csv[no-heading](jsonPayload.verified,jsonPayload.platform)" 2>/dev/null)
read -r TOT VER IOSV ANDV <<< "$(printf '%s\n' "$LOGS" | python3 -c '
import sys
rows=[l.strip().lower().split(",") for l in sys.stdin if l.strip()]
ver=[r for r in rows if r[0]=="true"]
print(len(rows), len(ver), sum(len(r)>1 and r[1]=="ios" for r in ver), sum(len(r)>1 and r[1]=="android" for r in ver))')"
SHARE=$(python3 -c "print(round($VER/$TOT,3) if $TOT else 0)")
[ "$IOSV" -ge 1 ] && pass "iOS tokens accepted ($IOSV calls)" || fail "no verified iOS call (DeviceCheck key not registered, or App Check build not used yet)"
[ "$ANDV" -ge 1 ] && pass "Android tokens accepted ($ANDV calls)" || fail "no verified Android call (Play Integrity / SHA-256 / build)"
if [ "$VER" -ge "$MIN_VERIFIED" ] && python3 -c "import sys; sys.exit(0 if $SHARE >= $MIN_SHARE else 1)"; then
  pass "verified $VER/$TOT (share $SHARE)"
else
  fail "verified $VER/$TOT (share $SHARE); need >= $MIN_VERIFIED verified and share >= $MIN_SHARE"
fi

echo "== 4b pending discovery queue deployed"
gcloud functions describe processDiscoveryQueue --gen2 --region=us-central1 --project=$PROJECT \
  --format="value(state)" 2>/dev/null | grep -qx ACTIVE \
  && pass "processDiscoveryQueue ACTIVE" || fail "processDiscoveryQueue not deployed (backend deploy with the queue)"
gcloud services list --enabled --project=$PROJECT --format="value(config.name)" | grep -qx cloudscheduler.googleapis.com \
  && pass "Cloud Scheduler API enabled" || fail "Cloud Scheduler API not enabled (needed by processDiscoveryQueue)"

echo "== 5 kill switch / pause"
ST=$(curl -s "${H[@]}" "https://firestore.googleapis.com/v1/projects/$PROJECT/databases/(default)/documents/melissa_usage/state" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); f=d.get("fields",{}); print("killed" if f.get("paidDisabled",{}).get("booleanValue") else "paused" if "outOfCreditsAt" in f else "clear")')
[ "$ST" = clear ] && pass "kill switch off, no out-of-credits pause" || fail "melissa_usage/state: $ST"

echo "== 6 365-day migration"
if gcloud auth application-default print-access-token >/dev/null 2>&1; then
  if (cd functions && node tool/migrate_cache_ttl.js verify --project=$PROJECT >/dev/null 2>&1); then pass "all cache records on the 365-day policy"
  else fail "TTL verify failed (run the blueprint deploy / migration first)"; fi
else fail "no gcloud ADC (gcloud auth application-default login)"; fi

echo
if [ $FAIL = 0 ]; then echo "ALL PASS — activation may be proposed to the project owner."; else echo "NOT READY — fix every FAIL above."; exit 1; fi
