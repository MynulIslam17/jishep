# Deploying the Melissa Cloud Functions to `gps-para-el-cielo`

> Current, complete step list: `docs/PRODUCTION_DEPLOY_CHECKLIST.md`
> (adds the 1st-gen `cleanupDeletedUser` service account, the upload
> ignore fix and the zero-spend `MELISSA_GLOBAL_DAILY_CREDITS=0` option).

Functions (2nd gen, Node 22, region `us-central1`):

| Function | What it does | Default |
|---|---|---|
| `enrichHousehold` | Melissa Personator Check (3 credits) + optional Property (9) for one household a user opens | on once deployed; app flag `ADDRESS_CHECKS` |
| `discoverNearby` | Melissa Reverse GeoCoder (2 credits/address) where Overture has < 50 homes | **off** (`MELISSA_GAP_FILL_ENABLED=false`); app flag `MELISSA_GAP_FILL` |
| `discoverOwners` | Melissa-first neighborhood, **cache first**: serves stored owner records (shared or per user) for free; only when `MELISSA_OWNER_DISCOVERY_ENABLED=true` does it pay for exactly the missing part (≤ 920 credits per request) | **cache-only** (`MELISSA_OWNER_DISCOVERY_ENABLED=false`) and refused while `MELISSA_ALLOW_OWNER_NAMES=false`; app flag `MELISSA_OWNERS`; see `docs/MELISSA_CACHE_STRATEGY.md` |
| `cleanupDeletedUser` | Auth trigger: when an account is deleted, removes `users/{uid}` with every subcollection (incl. server-written Melissa results), the user's usage counters and discovery locks | on once deployed (no Melissa call) |

Owner names: built (the recorded owner from Melissa Property becomes the
home's title after a check) but OFF (`MELISSA_ALLOW_OWNER_NAMES=false`)
until Melissa's license is confirmed to allow showing them. Resident names: not
available (Personator Append is not activated on the account, GE21).

## 1. What the client (project Owner) must do

Project: `gps-para-el-cielo` (number 1044715224614). Billing is already on
(Blaze).

### 1a. Enable APIs

```sh
gcloud services enable \
  cloudfunctions.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  run.googleapis.com \
  eventarc.googleapis.com \
  secretmanager.googleapis.com \
  firebaseappcheck.googleapis.com \
  iamcredentials.googleapis.com \
  --project gps-para-el-cielo
```
(Console: APIs & Services → Library → enable each.)

### 1b. Grant the developer account

Simplest: give the developer **Owner** on the project.

Least privilege (all on project `gps-para-el-cielo`, member
`user:<developer email>`):

| Role | Why |
|---|---|
| `roles/serviceusage.serviceUsageConsumer` | any CLI call (today's 403) |
| `roles/cloudfunctions.admin` | create/update functions |
| `roles/run.admin` | 2nd-gen functions run on Cloud Run; make callables invokable |
| `roles/iam.serviceAccountUser` on `1044715224614-compute@developer.gserviceaccount.com` | deploy as the runtime service account |
| `roles/secretmanager.admin` | create `MELISSA_CREDIT_LICENSE` and grant the runtime access |
| `roles/artifactregistry.admin` | the CLI creates `gcf-artifacts` and sets its image cleanup policy |
| `roles/cloudbuild.builds.editor` | start and read function builds |
| `roles/firebaserules.admin` | deploy Firestore rules (already possible via Firebase Admin) |

```sh
P=gps-para-el-cielo; U=user:DEVELOPER_EMAIL
for R in serviceusage.serviceUsageConsumer cloudfunctions.admin run.admin \
         secretmanager.admin artifactregistry.admin cloudbuild.builds.editor \
         firebaserules.admin; do
  gcloud projects add-iam-policy-binding $P --member="$U" --role="roles/$R"
done
gcloud iam service-accounts add-iam-policy-binding \
  1044715224614-compute@developer.gserviceaccount.com \
  --member="$U" --role=roles/iam.serviceAccountUser --project $P
```

### 1c. Build service account (new projects often fail without this)

```sh
SA=serviceAccount:1044715224614-compute@developer.gserviceaccount.com
for R in cloudbuild.builds.builder logging.logWriter artifactregistry.writer; do
  gcloud projects add-iam-policy-binding gps-para-el-cielo --member="$SA" --role="roles/$R"
done
```

## 2. What the developer runs (after approval)

```sh
cd functions && npm ci && npm test            # 76 tests, emulator only, network blocked
cd ..
# Rules first: the app saves `prayerIntention` and reads enrichment/gap_areas.
firebase deploy --only firestore:rules --project gps-para-el-cielo
# Secret (paste the CREDIT key when asked; never in a file in the repo).
firebase functions:secrets:set MELISSA_CREDIT_LICENSE --project gps-para-el-cielo
# Parameters: functions/.env.gps-para-el-cielo (create; not secret)
#   MELISSA_PER_USER_DAILY_LOOKUPS=20
#   MELISSA_GLOBAL_DAILY_CREDITS=0     # app-wide cap, ALL endpoints; 0 = no paid call
#   MELISSA_CACHE_DAYS=30            # 0 if Melissa does not allow caching
#   MELISSA_ALLOW_OWNER_NAMES=false  # true only after Melissa confirms the license
#   MELISSA_GAP_FILL_ENABLED=false   # true only after spending approval
#   MELISSA_GAP_PER_USER_DAILY=3
#   MELISSA_GAP_DAILY_CREDITS=300
#   MELISSA_GAP_VERIFY_RESIDENTIAL=false
#   ENFORCE_APP_CHECK=false          # true after App Check is registered
#   MELISSA_OWNER_DISCOVERY_ENABLED=false   # true = may SPEND (approval)
#   MELISSA_OWNER_SHARED_CACHE=false        # true only if Melissa allows sharing
#   MELISSA_OWNER_DAILY_CREDITS=2000 / MELISSA_OWNER_MONTHLY_CREDITS=20000
#   MELISSA_OWNER_REQUEST_MAX_CREDITS=920   # hard ceiling per request
#   MELISSA_OWNER_NEGATIVE_CACHE_DAYS=90    # exclusions (no owner data)
firebase deploy --only functions --project gps-para-el-cielo
# Production never replays recordings and never seeds owner data: the
# local pilot records stay on the developer's machine.
```

App builds:
- address checks: `--dart-define=ADDRESS_CHECKS=true`
- gap-filler (only after approval): `--dart-define=MELISSA_GAP_FILL=true`
  and `MELISSA_GAP_FILL_ENABLED=true` on the server.

## 3. Costs and limits

- `enrichHousehold`: 3 credits (12 with property). 20 per user per day;
  150 credits per day app-wide.
- `discoverNearby`: 2 credits per address returned (asks for need + 10);
  with residential verification +3 per address. 3 per user per day; 300
  credits per day app-wide. Unused credits are given back to the counters.
- After Melissa GE14 (out of credits) both functions pause for 6 h.
- Counters: `melissa_usage/{YYYY-MM-DD}` and `melissa_usage/month-YYYY-MM`
  (server-only): ESTIMATED credits (`ownerCredits`, `estimatedCredits`),
  cache hits/misses, Melissa requests, failed lookups. Melissa's own usage
  report is the billing authority.
- `discoverOwners`: per request ≤ 920 (`MELISSA_OWNER_REQUEST_MAX_CREDITS`),
  5 discoveries per user per day, 2,000 per day and 20,000 per month
  app-wide. A cache hit costs 0 credits and ~60–100 Firestore reads.
- Cloud Functions/Run/Build at this volume: within the free tier.

## 4. Local verification done (2026-11-21)

- `npm test` in `functions/`: 44 pass (Firestore emulator, fake Melissa,
  plus parsers checked against real Melissa responses for public buildings).
- Rules tests: 16 pass. Flutter: 402 pass.
- Functions emulator smoke test (dummy key): both functions load; signed
  out/in requests reach the code; gap-fill returns `gap_filler_disabled`;
  bad input → `invalid-argument`; Melissa rejects the dummy key →
  `license_invalid`, nothing charged. This found and fixed an App Check bug
  (a params object passed as `enforceAppCheck` counted as `true`).

## 5. Local verification done (2026-11-22, cache-first)

- Functions: 76 tests pass (`npm run test:local` with the dev emulator, or
  `npm test`); every test runs with `test/no_network.js` (no host other
  than localhost reachable; 0 blocked attempts recorded).
- Rules: 19 tests pass (`tool/firestore_rules_test`, separate emulator on
  port 8282).
- Flutter: 428 tests pass; `flutter analyze` clean.
- Spending guard (`functions/src/guard.js`): in the Functions emulator every
  Melissa request is answered from `functions/.melissa-recordings` or
  refused without network access. `MELISSA_REPLAY_ONLY` no longer matters;
  only `MELISSA_EMULATOR_LIVE=true` (never set) would allow a live call.
  This also closes a gap: `discoverNearby` used the global fetch in the
  emulator before.
- Emulator call for the pilot test user: 50 named homes, `complete`, 0
  credits, 61 Firestore reads, on every repeat.

Deploy order when approved: rules → functions (`discoverOwners` stays
cache-only until spending is approved) → app build. See
`docs/ARCHITECTURE.md` §7.
