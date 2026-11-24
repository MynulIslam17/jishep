# Production deployment — GPS PARA EL CIELO

**Authoritative deploy document** (blueprint §23, §25). Supersedes
`docs/PRODUCTION_DEPLOY_CHECKLIST.md` and `docs/DEPLOY_FUNCTIONS.md`.

> Status 2026-11-24: every change from the 2026-11-24 blueprint work is
> Production runs the **2026-11-24 blueprint backend** (see Release log). Paid Melissa is **ON** (2,000/day, 9,000/month). App Check was verified with simulator **debug tokens**, not real devices (owner-accepted 2026-11-24).
> Deploying needs the project owner's explicit approval.

## 1. Environments

| Project | Role | Notes |
|---|---|---|
| `gps-para-el-cielo` (number 1044715224614, Firestore `nam5`, Blaze) | **production** | the client's project; apps registered (iOS `1:1044715224614:ios:8fe76620733d1f4217b0e7`, Android `…:android:f1cd5fefe98d5d2417b0e7`) |
| `gps-cielo` | rollback / legacy | keep intact until the client confirms cutover; `gcloud config` default project — always pass `--project` |
| `cielo-63925` | **never** read or modify | all tools refuse it |
| local emulators | development | `tool/emulators.sh` (auth, firestore, functions; data in `.emulator-data/`, Melissa replay-only) |

## 2. Prerequisites (state as of 2026-11-23)

- Developer account: `roles/owner` + `firebase.admin` on `gps-para-el-cielo`.
- APIs enabled: cloudfunctions, cloudbuild, artifactregistry, run, eventarc,
  secretmanager, cloudbilling, iam (+ firebaseextensions). For App Check
  later: `firebaseappcheck.googleapis.com`.
- Org policy `iam.automaticIamGrantsForDefaultServiceAccounts` is
  **enforced**: default service accounts get no automatic roles. Granted
  (2026-11-23): compute SA `1044715224614-compute@developer.gserviceaccount.com`
  → `roles/cloudbuild.builds.builder`, `roles/datastore.user`; App Engine SA
  `gps-para-el-cielo@appspot.gserviceaccount.com` → `roles/datastore.user`.
  No service-account keys exist; none may be created.
- Secret `MELISSA_CREDIT_LICENSE` (automatic replication, version 1); the
  runtime compute SA has `secretAccessor` on it.
- Artifact Registry `gcf-artifacts` cleanup policy: images older than 1 day.
- Functions: `enrichHousehold`, `discoverNearby`, `discoverOwners` (2nd gen,
  us-central1, compute SA), `cleanupDeletedUser` (1st gen Auth trigger, App
  Engine SA).
- Operator tools (Admin SDK) need `gcloud auth application-default login`.
- Java 21 for local emulators:
  `export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home`.
- Never a bare `firebase deploy` (it would also deploy Hosting).

## 3. Pre-deploy gate

1. All suites green (`docs/TESTING_STRATEGY.md`): functions 121, rules 25,
   Flutter 457 (+1 skip), `flutter analyze` clean.
2. Commit the reviewed tree; deploy from that commit.
3. `functions/.env.gps-para-el-cielo` safety values: `MELISSA_GLOBAL_DAILY_CREDITS=0`,
   `MELISSA_OWNER_DISCOVERY_ENABLED=false`, `MELISSA_GAP_FILL_ENABLED=false`,
   `MELISSA_CACHE_DAYS=365`, `MELISSA_OWNER_REQUIRE_VERIFIED=true`,
   `MELISSA_OWNER_LOCATION_TOLERANCE_M=250`, `ENFORCE_APP_CHECK=false`
   (until §4 of `docs/SECURITY.md`).
4. Upload check: `firebase.json` ignores `.melissa-recordings`,
   `.secret.local`, `.env.local`, `test`, `tool` (asserted by
   `zero_budget.test.js`).

## 4. One-command rollout: `tool/deploy_blueprint.sh`

```sh
tool/deploy_blueprint.sh --approve=gps-para-el-cielo
```

Refuses without `--approve=gps-para-el-cielo`; unsets
`FIRESTORE_EMULATOR_HOST`; stops at the first failure.

| Step | What | Output / check |
|---|---|---|
| 0 | safety checks above + ADC present | refuses on any mismatch |
| 1 | backups to `.local-backups/prod-blueprint-<ts>/` (mode 700): current Firestore release + `ruleset.txt`, `functions_list.txt`, TTL backup `ttl-backup-<id>.json` (old `expiresAt` + exact `updateTime` per cache document) | |
| 2 | `firebase deploy --dry-run` (functions, rules, indexes) | |
| 3 | rules + indexes: location lock, `primary_locations`, `location_corrections`, audit index `location_corrections(uid, at)` | |
| 4 | all functions (server-side location, verified gate, kill switch, 365-day default, cleanup fix) | |
| 5 | `migrate_cache_ttl.js apply` + `verify` on root `owner_properties` (status `named`) and `owner_scans`: `expiresAt = checkedAt/scannedAt + 365 d`; only extends, never deletes, `updateTime` precondition | verify must be OK |
| 6 | live check: unauthenticated `discoverOwners` → `sign_in_required`; `melissa_ops.js status` | |

Rehearsed on the local emulator 2026-11-24 (pilot data): plan 51 eligible
(50 named + 1 scan; 2 negatives untouched), apply 51 updated, verify OK,
re-apply 0 updated (idempotent). Local backups:
`.local-backups/pre-ttl365-20261124-112853` (emulator export) and
`.local-backups/ttl365-local-20261124/`.

Expected production effect of step 5: the 53 imported docs (52
`owner_properties` incl. 2 negatives, 1 `owner_scans`) → 51 extended from
2026-12-22 to 2027-11-22.

## 5. Deploy order

1. **Rules + functions first** (the script), then
2. **mobile build** with the fixed-location UI.

The new app's setup write (`AuthService.updateLocation`) stamps
`locationConfirmedAt`/`locationVersion`; if the old rules are still live it
gets `permission-denied` and retries without them, so the order is safe
either way. Once the new rules are live, the store app 1.0.0/1.0.1
"My address" editor fails with a permission error (intended).

## 6. Rollback (per component)

| Component | Command |
|---|---|
| Rules | re-release the saved ruleset name (`ruleset.txt`) in console › Firestore › Rules › history, or `git checkout <prev> -- firestore.rules && firebase deploy --only firestore:rules --project gps-para-el-cielo` |
| Indexes | the added index is harmless; leave it |
| Functions | `git checkout <prev> -- functions && firebase deploy --only functions --project gps-para-el-cielo` |
| TTL migration | `cd functions && node tool/migrate_cache_ttl.js rollback --project=gps-para-el-cielo --in=<ttl-backup.json> --approve=gps-para-el-cielo` (restores only docs still carrying that migration id) |
| Paid stop | `cd functions && node tool/melissa_ops.js kill --project=gps-para-el-cielo --reason="..." --approve=gps-para-el-cielo` |
| Mobile | halt the staged rollout / expire the TestFlight build |

`primary_locations` pins written after deploy are harmless after a
functions rollback (the old code ignores them).

## 7. Controlled live Melissa activation (not yet authorized)

Paid discovery stays **OFF**. Blockers as of 2026-11-24: App Check not yet
registered / released / deployed, and the owner's approval. Credits are no
longer the blocker: balance **10,250**, Auto-Refill off (2026-11-24), about
11–14 new 50-home areas at ~700–920 each. Requires the project owner's written approval of a
specific budget.

Preconditions:

1. Credits bought; balance read in the Melissa portal and recorded.
2. App Check enforced (`docs/SECURITY.md` §4).
3. Blueprint rollout (§4) deployed and verified.
4. A test account with a verified sign-in whose saved home is the chosen
   uncached residential area (not an existing cached area).

Procedure (one area, once):

1. Set in `functions/.env.gps-para-el-cielo`:
   `MELISSA_OWNER_DISCOVERY_ENABLED=true`, `MELISSA_GLOBAL_DAILY_CREDITS=920`,
   `MELISSA_OWNER_REQUEST_MAX_CREDITS=920`, `MELISSA_OWNER_DAILY_CREDITS=920`,
   `MELISSA_OWNER_PER_USER_DAILY=1`. Deploy `functions:discoverOwners`.
2. Open the test account once (one request).
3. `node tool/melissa_ops.js report --project=gps-para-el-cielo --days=1`
   — compare estimated credits with the Melissa portal balance change.
   Stop (kill switch) on any mismatch > 10 % or error.
4. Repeat the same request: must return `cached: true`, `credits: 0`, and
   the portal balance must not move.
5. A second account 50–200 m away: must be served from the cache (0 credits).
6. Turn discovery back off (`false`, budget `0`, redeploy) or set
   owner-approved steady-state limits. Record everything in the Release log.

## 8. Mobile release vs backend deploy

These are separate. A backend deploy changes nothing in the stores; a store
release does not deploy rules or functions.

- Version: `pubspec.yaml` `1.0.2+2` (App Store approved 1.0.0). About shows
  `AppConfig.appVersion` (1.0.2 on 2026-11-24).
- Codemagic workflows (`codemagic.yaml`): `flutter-ci` (analyze + test),
  `android-debug`, `ios-simulator`, `ios-testflight` (App Store Connect
  integration; `submit_to_testflight: false` — uploads without external
  beta review).
- Android: `flutter build appbundle --release` with the upload key in
  `android/key.properties`; Play Console steps in `docs/store_release.md`.
- Release builds use live Firebase; build with
  `--dart-define=MELISSA_OWNERS=true` for owner names.

## 9. Release log

| Date | Component | What | Status |
|---|---|---|---|
| 2026-11-21 | Auth/apps | apps + providers on gps-para-el-cielo; rules + indexes deployed | deployed |
| 2026-11-23 | Rules | ruleset `bcaf80a0-c045-45a6-b44b-d58c460a9cd8` (rollback: `632b077d-202e-457f-ba7c-e9da1b44a13d`) | deployed |
| 2026-11-23 | Functions | 4 functions ACTIVE, paid Melissa off (budget 0) | deployed |
| 2026-11-23 | Data | 53 owner docs imported (52 properties + 1 scan); owner names + shared cache ON; expire 2026-12-22 | deployed |
| 2026-11-24 06:52 UTC | Rules + indexes | ruleset `9e375e8c-af3f-41f6-871b-0e6565520361`: location lock, `primary_locations`, `location_corrections` (rollback: `bcaf80a0-c045-45a6-b44b-d58c460a9cd8`) | **deployed** (owner-approved) |
| 2026-11-24 06:53 UTC | Functions | 4 functions ACTIVE: server-side location pin, verified gate, App Check soft gate, kill switch, 365-day cache, counters, cleanup fix. Budget 0, discovery OFF, `ENFORCE_APP_CHECK=false` | **deployed** (owner-approved) |
| 2026-11-24 | Data | 365-day TTL migration `ttl365-20261124T065121-b48410`: 53 updated, verify ok, preservation 53/53 unchanged | **deployed** |
| 2026-11-24 | Source | deployed from the working tree on top of commit `0f4bf97` (uncommitted changes); log `.local-backups/deploy-20261124-125113.log`, backups `.local-backups/prod-blueprint-20261124-125114/` | commit pending |
| 2026-11-24 09:00 UTC | Queue | pending discovery queue: `processDiscoveryQueue` (every 30 min, does nothing while paid is OFF), `discovery_queue` server-only rule (ruleset `948b4596-f4b7-400e-9a1d-4174fb1af966`, rollback `9e375e8c-af3f-41f6-871b-0e6565520361`), index `discovery_queue(status, createdAt)`, Cloud Scheduler API enabled. TTL re-verified 53/53. Log `.local-backups/deploy-20261124-145958.log`, backups `.local-backups/prod-blueprint-20261124-145959/` | **deployed** (owner-approved) |
| 2026-11-24 09:20 UTC | **Paid Melissa ON** | owner-approved: `MELISSA_OWNER_DISCOVERY_ENABLED=true`, 2,000 credits/day, 9,000/month (balance 10,250), 920/request, 5/user/day; `discoverOwners` + `processDiscoveryQueue` only (enrichHousehold / discoverNearby still 0). App Check requirement kept (`--app-check-pending`): no credit can be spent until the App Check consoles are done and 1.0.2 is released. Env backup `.local-backups/activate-20261124-152000/env.before`; log `.local-backups/activate-20261124-151939.log`. Credits spent at activation: 0 | **live** |
| 2026-11-24 09:33 UTC | **Paid Melissa OFF again** | owner instruction: keep paid disabled until the production security checks really pass, no bypass. `.env` restored from `activate-20261124-152000/env.before`, `discoverOwners` + `processDiscoveryQueue` redeployed: discovery false, global daily 0. The `--app-check-pending` option was removed from the preflight and activation scripts. 0 credits were spent while it was on. Log `.local-backups/deactivate-20261124-153256.log` | **live** |
| 2026-11-24 09:50 UTC | **Paid Melissa ON** | owner-approved: 2,000/day, 9,000/month, 920/request, 5/user/day, 365-day cache, shared cache, 250 m home lock, queue on. App Check verified with **debug tokens from the iOS simulator and Android emulator** (2 accepted calls each), NOT real devices; preflight run with `--min-verified=4 --min-share=0.5` (owner-accepted; the 3 unverified calls were the operator's own unauthenticated checks). Store users get new lookups only after the iOS DeviceCheck key and the Play app-signing SHA-256 are added. Debug tokens: `.local-backups/APP_CHECK_DEBUG_TOKENS.txt` (revocable). Log `.local-backups/activate-20261124-155035.log` | **live** |
| 2026-11-24 09:55 UTC | Live test | ONE new neighborhood (Eastlake, Chula Vista 91914), production test account (`.local-backups/PROD_TEST_LOGIN.txt`), iOS simulator: 50 named homes, complete, **668 credits** (100 addresses, 52 property lookups, 0 errors). Android emulator, same area: 50 from cache, 0 credits. Month total 668 | **passed** |
| 2026-11-24 | App Check consoles | Android: Play Integrity registered (debug + upload SHA-256; Play API enabled). iOS: DeviceCheck key `6D7Z4G7XQ5` (team T83PP9TMXS) created in Apple Developer and uploaded to Firebase by the owner (`privateKeySet: true`); App Attest also registered. Still open: Play **app-signing** SHA-256 + Play Integrity Cloud link (Play Console owner account) | **iOS done, Android partial** |
| 2026-11-24 | App | fixed-location UI, App Check client, pending-queue note, version 1.0.2+2 | **not built/uploaded** |
| — | Melissa | live paid discovery | **blocked** (App Check registration + build, owner approval); `tool/preflight_paid.sh` |
