# Incident response — GPS PARA EL CIELO

Blueprint §24, §29. Runbooks with exact commands. Production project:
`gps-para-el-cielo`. Never touch `cielo-63925`. Always pass `--project`.

Operator setup (once per machine):

```sh
gcloud auth login && gcloud auth application-default login
cd "<repo>/functions"
P=gps-para-el-cielo
```

Status at a glance:

```sh
node tool/melissa_ops.js status --project=$P            # kill switch + today
node tool/melissa_ops.js report --project=$P --days=30  # counters, warnings
firebase functions:log --project $P --only discoverOwners
```

> The kill switch, verified gate and location pin exist in the repository
> but are **not deployed yet** (2026-11-24). Until `tool/deploy_blueprint.sh`
> runs, production's protection is `MELISSA_GLOBAL_DAILY_CREDITS=0` and
> `MELISSA_OWNER_DISCOVERY_ENABLED=false` (no paid call is possible).

## 1. Unexpected Melissa spend

1. **Stop all paid calls now** (takes effect on the next request, no redeploy):
   ```sh
   node tool/melissa_ops.js kill --project=$P --reason="unexpected spend <ticket>" --approve=$P
   ```
2. Belt and braces: set `MELISSA_GLOBAL_DAILY_CREDITS=0` and
   `MELISSA_OWNER_DISCOVERY_ENABLED=false` in `functions/.env.$P`, then
   `firebase deploy --only functions --project $P`.
3. Compare `melissa_ops.js report` with the Melissa portal usage. The
   portal is the billing authority; counters are estimates.
4. Look for `deniedSecurity` / `deniedBudget` spikes and `discovery_jobs`
   with many `attempts` (Firestore console).
5. Unkill only after the cause is fixed and the owner approves:
   ```sh
   node tool/melissa_ops.js unkill --project=$P --reason="resolved <ticket>" --approve=$P
   ```

## 2. Melissa out of credits (GE14)

Automatic: the functions record `melissa_usage/state.outOfCreditsAt` and
pause paid calls for 6 h; cached data is still served; apps show "More homes
for this area will be added soon." Action: buy credits (owner), confirm the
balance in the portal, then wait out the pause or clear it:

```sh
# Firestore console: melissa_usage/state → delete field outOfCreditsAt
```

## 3. Melissa outage / timeouts / rate limits

Uncharged errors (`network`, `timeout`, `rate_limited`, `unavailable`) give
the reservation back; finished lookups are stored as they arrive, so the
next request resumes. If the outage persists, use the kill switch (§1) to
stop retries; nothing is lost.

## 4. Firestore outage

Callables return `internal`; the app shows its error state and keeps
cached Firestore data offline. No paid call can happen without a
successful reservation transaction. Watch status.cloud.google.com; no
action in the app. After recovery check `discovery_jobs` for leases stuck in
`running` — they expire by themselves (150 s).

## 5. Leaked Melissa key

1. Kill switch (§1).
2. Rotate in the Melissa portal (new credit license); revoke the old one.
3. New secret version and redeploy:
   ```sh
   firebase functions:secrets:set MELISSA_CREDIT_LICENSE --project $P
   firebase deploy --only functions --project $P
   gcloud secrets versions list MELISSA_CREDIT_LICENSE --project $P
   gcloud secrets versions disable <old-version> --secret=MELISSA_CREDIT_LICENSE --project $P
   ```
4. Update `~/.config/gps-cielo/melissa.env` (mode 600). Check git history
   and logs for the key (`git log -p -S '<prefix>'`); never paste it anywhere.

## 6. Abusive account

1. Firebase console › Authentication › disable the user (stops new tokens).
2. If credit-related, kill switch (§1) while investigating.
3. Their counters: `melissa_usage/<day>/users/<uid>`. Shared cache data they
   triggered is legitimate and stays.
4. Deleting the account runs `cleanupDeletedUser` (removes their private
   data, pin and per-user locks).

## 7. Bad deploy

| Part | Rollback |
|---|---|
| Functions | `git checkout <good-commit> -- functions && firebase deploy --only functions --project $P` |
| Rules | console › Firestore › Rules › history › re-release the previous ruleset (name in `.local-backups/prod-blueprint-<ts>/ruleset.txt`), or deploy `firestore.rules` from the good commit |
| App | halt the Play staged rollout; expire the TestFlight build; ask App Review to remove a bad version if needed |

## 8. A user's location is wrong (moved / wrong address)

Users ask through Contact support (`support_messages`). Verify identity,
then:

```sh
node tool/location_admin.js history --project=$P --uid=<uid>
node tool/location_admin.js correct --project=$P --uid=<uid> \
  --lat=<lat> --lon=<lon> --address="<full US address>" \
  --reason="moved — support ticket <id>" --operator="<your name>" --approve=$P
```

Max 2 corrections per user per 365 days (`rate_limited`); prayer history is
kept; the audit record is `location_corrections/<id>`. Corrections buy
nothing by themselves.

## 9. 365-day TTL migration problem

```sh
node tool/migrate_cache_ttl.js verify --project=$P
node tool/migrate_cache_ttl.js rollback --project=$P \
  --in=../.local-backups/prod-blueprint-<ts>/ttl-backup-<id>.json --approve=$P
```

Rollback restores the old `expiresAt` only on documents still carrying that
migration id; nothing is deleted.

## 10. After any incident

Record: timeline, credits affected (portal vs counters), commands run,
follow-ups. Update `docs/PRODUCTION_DEPLOYMENT.md` › Release log if anything
was deployed or rolled back.
