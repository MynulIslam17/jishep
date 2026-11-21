#!/bin/zsh
# Daily production seeding on the free (Spark) plan: 20,000 writes a day,
# reset at 00:00 Pacific. Run by the LaunchAgent
# ~/Library/LaunchAgents/com.gpscielo.seed-daily.plist at 14:10 local time
# (00:10 PST); a run missed while the Mac slept happens on wake.
#
# Each Pacific day, at most once, with an 18,000-write budget:
#   1. New Jersey with --rewrite (only cells not yet written with the
#      current files; 0 once done),
#   2. California with what is left of the budget.
# Days used by the one-off day-2 run (reseed_day2.sh) are skipped. When
# both areas are fully loaded, the LaunchAgent removes itself.
#
#   DRY=1 zsh seed_daily.sh   # show what would happen; reads/writes nothing
set -u
export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
cd "/Users/mynul/develop/projects/Gps_cielo copy/tool/overture_cells" || exit 1

LABEL=com.gpscielo.seed-daily
PLIST=~/Library/LaunchAgents/$LABEL.plist
LOG=out/seed_production_daily.log
STAMP=out/.seed_progress/daily_last_run
BUDGET=18000
DRY=${DRY:-0}
PST_DAY=$(TZ=America/Los_Angeles date +%Y-%m-%d)

log() { echo "[$(date)] $*" | tee -a $LOG; }
notify() { osascript -e "display notification \"$1\" with title \"GPS Cielo seeding\"" 2>/dev/null; }

# "N to go" from a dry-run (no reads, no writes).
to_go() {
  node seed_firestore.js "$1" ${2:-} 2>/dev/null |
    grep -oE "[0-9,]+ to go" | grep -oE "[0-9,]+" | tr -d ,
}

finish_if_done() {
  local nj ca
  nj=$(to_go out/new_jersey --rewrite); ca=$(to_go out/california)
  if [ "${nj:-x}" = 0 ] && [ "${ca:-x}" = 0 ]; then
    log "New Jersey and California are fully loaded. Removing the daily job."
    notify "New Jersey and California are fully loaded."
    [ "$DRY" = 1 ] && return 0
    rm -f "$PLIST"
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
    exit 0
  fi
}

# Not before the quota reset (+5 min).
if [ "$(TZ=America/Los_Angeles date +%H%M)" -lt 0005 ]; then exit 0; fi

# At most once per Pacific day (a wake-up retry must not spend twice).
if [ "$DRY" != 1 ] && [ "$(cat $STAMP 2>/dev/null)" = "$PST_DAY" ]; then exit 0; fi

# The one-off day-2 run owns its day's quota.
if pgrep -f reseed_day2.sh >/dev/null; then
  log "Day-2 run (reseed_day2.sh) is active; skipping $PST_DAY."
  [ "$DRY" = 1 ] || echo $PST_DAY > $STAMP
  exit 0
fi
if [ -f out/seed_production_day2.log ] &&
   [ "$(TZ=America/Los_Angeles date -r out/seed_production_day2.log +%Y-%m-%d)" = "$PST_DAY" ] &&
   grep -q "^\[.*\] ===" out/seed_production_day2.log; then
  log "Day-2 run already used the quota of $PST_DAY; skipping."
  [ "$DRY" = 1 ] || echo $PST_DAY > $STAMP
  exit 0
fi

finish_if_done

if [ "$DRY" = 1 ]; then
  log "DRY: would run for $PST_DAY: New Jersey $(to_go out/new_jersey --rewrite) to go," \
      "California $(to_go out/california) to go, budget $BUDGET."
  exit 0
fi

echo $PST_DAY > $STAMP
log "=== $PST_DAY: New Jersey (--rewrite, only cells not yet written with current files)"
out=$(node seed_firestore.js out/new_jersey --write --rewrite --max-writes $BUDGET 2>&1 | tr '\r' '\n')
echo "$out" | grep -vE "^\S*\s*written" >> $LOG
NJ=$(echo "$out" | grep -oE "^Done: [0-9,]+ written" | tail -1 | grep -oE "[0-9,]+" | tr -d ,)
if [ -z "$NJ" ]; then
  log "New Jersey run failed (see above); nothing more today."
  notify "Seeding failed today. See tool/overture_cells/$LOG"
  exit 1
fi
REST=$((BUDGET - NJ))
log "New Jersey wrote $NJ; California budget $REST"

CA=0
if [ $REST -gt 0 ]; then
  log "=== $PST_DAY: California"
  out=$(node seed_firestore.js out/california --write --max-writes $REST 2>&1 | tr '\r' '\n')
  echo "$out" | grep -vE "^\S*\s*written" >> $LOG
  CA=$(echo "$out" | grep -oE "^Done: [0-9,]+ written" | tail -1 | grep -oE "[0-9,]+" | tr -d ,)
  if [ -z "$CA" ]; then
    log "California run failed (see above)."
    notify "California seeding failed today. See tool/overture_cells/$LOG"
    exit 1
  fi
fi

log "Finished $PST_DAY: New Jersey $NJ written, California ${CA:-0} written."
notify "Today: New Jersey $NJ, California ${CA:-0} cells uploaded."
finish_if_done
