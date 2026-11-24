# 365-day cache migration and deployment verification checklist

Prepared **2026-11-24**, not run. Production is `gps-para-el-cielo` (never
`cielo-63925`). Nothing here calls Melissa or spends credits. Run only after
the project owner explicitly approves the deployment.

## 0. Production facts (read-only checks, 2026-11-24)

| What | Value | How it was read |
|---|---|---|
| Shared cache | **53 records**: 50 `owner_properties` named + 2 `not_found` + 1 `owner_scans` | Firestore REST `runAggregationQuery` / `list` (GET only) |
| Their expiry today | 50 named + scan → **2026-12-22**; 2 not_found → 2027-02-20 | same |
| Other collections | `discovery_jobs` 0, `primary_locations` 0, `owner_areas` 0 | same |
| `melissa_usage/state` | does not exist (no kill switch set, no out-of-credits pause) | same |
| `melissa_usage/month-2026-11` | does not exist (**0 credits reserved this month**) | same |
| Usage days | 2026-11-23: 38 cache misses; 2026-11-24: 14 cache misses; no `ownerCredits` | same |
| Deployed functions | `discoverOwners`, `enrichHousehold`, `discoverNearby` ACTIVE, updated 2026-11-23 06:12 UTC | `gcloud functions describe` |
| Deployed limits | `MELISSA_GLOBAL_DAILY_CREDITS=0` (**no paid call possible**), `MELISSA_OWNER_DISCOVERY_ENABLED=false`, `MELISSA_GAP_FILL_ENABLED=false`, owner daily 2000, monthly 20000, per request 920, per user 5/day, `MELISSA_CACHE_DAYS=30`, negative 90, `ENFORCE_APP_CHECK=false` | same |
| Melissa account balance | **10,250 credits**, Auto-Refill **NO** (2026-11-24; was 250 on 2026-11-23) | Melissa › My Account page, read in the browser (no API call) |

Why it matters: without the migration the 53 paid records stop being
served as fresh on 2026-12-22 (no data is deleted, but users would see no
owner names, and a later paid run would buy them again).

## 1. Before (all must be ✅)

- [ ] Project owner's written approval for this deploy (date, scope).
- [ ] `git status` clean on the commit being deployed; commit hash noted.
- [ ] Tests green: `cd functions && npm test` (133), `cd tool/firestore_rules_test && npm test` (27), `flutter test`, `flutter analyze`.
- [ ] `functions/.env.gps-para-el-cielo`: `MELISSA_GLOBAL_DAILY_CREDITS=0`, `MELISSA_OWNER_DISCOVERY_ENABLED=false`, `MELISSA_GAP_FILL_ENABLED=false`, `MELISSA_CACHE_DAYS=365`, `MELISSA_OWNER_NEGATIVE_CACHE_DAYS=365`, `MELISSA_OWNER_REQUIRE_VERIFIED=true`, `MELISSA_REQUIRE_APP_CHECK=true`, `ENFORCE_APP_CHECK=false` (the script checks these itself).
- [ ] `gcloud auth application-default login` done (Admin SDK tools need ADC; it was missing on 2026-11-24).
- [ ] Read-only dry look: `cd functions && node tool/migrate_cache_ttl.js plan --project=gps-para-el-cielo --verbose`. Expect **owner_properties 52, owner_scans 1, eligible 53, extend 53**. Stop if different and find out why.
- [ ] Before 2026-12-22 (after that date the records are already stale; the migration still restores them, since it extends from `checkedAt`).

## 2. Run

```
tool/deploy_blueprint.sh --approve=gps-para-el-cielo
```

Steps and stop points (it stops at the first failure):

1. Safety checks (env values above, ADC, project ≠ cielo-63925).
2. Backups → `.local-backups/prod-blueprint-<ts>/` (mode 700):
   live ruleset name, functions list, **TTL backup** (each document's
   path, old `expiresAt`, exact `updateTime`, and a **SHA-256 fingerprint of
   every cache document's content**).
3. `firebase deploy --dry-run`.
4. Firestore rules + indexes.
5. Cloud Functions.
6. TTL `apply` (only `expiresAt` + `ttlPolicy` written, with an
   `updateTime` precondition, so a document that changed is skipped, not
   overwritten) then `verify --in=<backup>`.
7. Live check: unauthenticated `discoverOwners` → `sign_in_required`.

## 3. After: verification (all must be ✅)

- [ ] `verify` printed `"ok": true` and
      `"preservation": {"ok": true, "before": 53, "now": 53, "missing": [], "changed": []}`.
      This proves that every one of the 53 records still exists with the
      same names, addresses, MAKs and timestamps. Only the expiry changed.
- [ ] `plan` again: `extend 0`, `alreadyOk 53`.
- [ ] Spot check one document in the console: `expiresAt` = `checkedAt` + 365 d; `ttlPolicy.previousExpiresAt` = 2026-12-22…
- [ ] `gcloud functions describe discoverOwners --gen2 --region=us-central1 --project=gps-para-el-cielo` shows `MELISSA_CACHE_DAYS=365`, `MELISSA_GLOBAL_DAILY_CREDITS=0`, `MELISSA_REQUIRE_APP_CHECK=true`.
- [ ] `node tool/melissa_ops.js status --project=gps-para-el-cielo`: credits today 0, month 0.
- [ ] App (store build) on a pilot account in the pilot area: owner names still shown; Profile shows the neighborhood read-only.
- [ ] Old build (1.0.0), if one is at hand: neighborhood and prayer list load; "Change home address" → "Address Not Saved" (expected, see [COMPATIBILITY_AUDIT.md](COMPATIBILITY_AUDIT.md)).
- [ ] Logs: no `outcome: crash` for 30 min (`jsonPayload.event="owners"`).
- [ ] Record the commit, time and backup folder in [PRODUCTION_DEPLOYMENT.md](PRODUCTION_DEPLOYMENT.md) (release log).

## 4. Rollback (independent)

| Part | Command |
|---|---|
| TTL | `cd functions && node tool/migrate_cache_ttl.js rollback --project=gps-para-el-cielo --in=<backup.json> --approve=gps-para-el-cielo` (restores the old expiry only on documents still carrying this migration's id) |
| Functions | `git checkout <previous> -- functions && firebase deploy --only functions --project gps-para-el-cielo` |
| Rules | re-release the saved ruleset (`backups/ruleset.txt`) in Console › Firestore › Rules › history |
| Stop all paid calls | `node tool/melissa_ops.js kill --project=gps-para-el-cielo --reason="…" --approve=gps-para-el-cielo` |

Nothing in the rollback deletes data.

## 5. Not part of this deploy

Paid Melissa (`MELISSA_OWNER_DISCOVERY_ENABLED`, `MELISSA_GLOBAL_DAILY_CREDITS`)
stays off. Turning it on needs, separately: the App Check consoles done
and an App Check build released ([APP_CHECK.md](APP_CHECK.md)), enough
Melissa credits (one new area ≈ 700–920), and the owner's explicit approval.
