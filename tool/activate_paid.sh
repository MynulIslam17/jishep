#!/usr/bin/env bash
# FINAL STEP — turns on real Melissa owner lookups (this SPENDS CREDITS).
# PREPARED, NOT RUN. Only after:
#   - tool/preflight_paid.sh prints ALL PASS, and
#   - the project owner explicitly approves activation with these limits.
#
#   tool/activate_paid.sh --approve=gps-para-el-cielo --daily=2000 --monthly=9000
#
# What it changes (functions/.env.gps-para-el-cielo, then deploys ONLY
# discoverOwners and processDiscoveryQueue (the pending queue, which resumes
# budget-refused areas under the same limits), so enrichHousehold /
# discoverNearby keep the old 0 budget):
#   MELISSA_OWNER_DISCOVERY_ENABLED=true
#   MELISSA_GLOBAL_DAILY_CREDITS=<daily>      (app-wide cap per UTC day)
#   MELISSA_OWNER_DAILY_CREDITS=<daily>
#   MELISSA_OWNER_MONTHLY_CREDITS=<monthly>   (keep below the Melissa balance)
# Unchanged: per request 920, per user 5/day, max 80 lookups, 1 mile,
# verified-account + App Check + 250 m location gates.
#
# EMERGENCY STOP (instant, no deploy, every paid endpoint):
#   (cd functions && node tool/melissa_ops.js kill --project=gps-para-el-cielo \
#      --reason="..." --approve=gps-para-el-cielo)
# FULL ROLLBACK: restore the .env backup printed below and
#   firebase deploy --only functions:discoverOwners,functions:processDiscoveryQueue --project gps-para-el-cielo
set -euo pipefail
cd "$(dirname "$0")/.."
PROJECT=gps-para-el-cielo
ENV=functions/.env.$PROJECT
APPROVE=""; DAILY=""; MONTHLY=""; PREFLIGHT_ARGS=()
for a in "$@"; do
  case "$a" in
    --approve=*) APPROVE="${a#*=}" ;;
    --daily=*) DAILY="${a#*=}" ;;
    --monthly=*) MONTHLY="${a#*=}" ;;
    # Preflight thresholds (every App Check check still has to PASS; the
    # values are printed by the preflight and kept in the log).
    --min-verified=*|--min-share=*) PREFLIGHT_ARGS+=("$a") ;;
    *) echo "unknown argument: $a" >&2; exit 2 ;;
  esac
done
[ "$APPROVE" = "$PROJECT" ] || { echo "refused: --approve=$PROJECT is required" >&2; exit 2; }
[[ "$DAILY" =~ ^[0-9]+$ && "$MONTHLY" =~ ^[0-9]+$ ]] || { echo "refused: --daily=<credits> --monthly=<credits> required" >&2; exit 2; }
[ "$DAILY" -le 5000 ] && [ "$MONTHLY" -le 20000 ] && [ "$DAILY" -le "$MONTHLY" ] \
  || { echo "refused: daily <= 5000, monthly <= 20000, daily <= monthly" >&2; exit 2; }

echo "== preflight (must be ALL PASS)"
tool/preflight_paid.sh "${PREFLIGHT_ARGS[@]+"${PREFLIGHT_ARGS[@]}"}"

TS=$(date +%Y%m%d-%H%M%S)
BK=.local-backups/activate-$TS; mkdir -p "$BK"; chmod 700 "$BK"
cp "$ENV" "$BK/env.before"
setv() { if grep -qE "^$1=" "$ENV"; then sed -i '' "s/^$1=.*/$1=$2/" "$ENV"; else echo "$1=$2" >> "$ENV"; fi; }
setv MELISSA_OWNER_DISCOVERY_ENABLED true
setv MELISSA_GLOBAL_DAILY_CREDITS "$DAILY"
setv MELISSA_OWNER_DAILY_CREDITS "$DAILY"
setv MELISSA_OWNER_MONTHLY_CREDITS "$MONTHLY"
echo "== env change (backup: $BK/env.before)"
diff "$BK/env.before" "$ENV" || true

echo "== deploy discoverOwners + processDiscoveryQueue only"
firebase deploy --only functions:discoverOwners,functions:processDiscoveryQueue --project $PROJECT --non-interactive

echo "== after"
gcloud functions describe discoverOwners --gen2 --region=us-central1 --project=$PROJECT \
  --format="value(serviceConfig.environmentVariables.MELISSA_OWNER_DISCOVERY_ENABLED,serviceConfig.environmentVariables.MELISSA_GLOBAL_DAILY_CREDITS)"
(cd functions && node tool/melissa_ops.js status --project=$PROJECT)
echo "ACTIVE. Watch: node functions/tool/melissa_ops.js report --project=$PROJECT --days=1"
echo "NOTE: $ENV now has a non-zero MELISSA_GLOBAL_DAILY_CREDITS; a later full"
echo "functions deploy also gives enrichHousehold/discoverNearby that budget"
echo "(still behind App Check, verified and per-user limits)."
