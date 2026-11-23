# Production deployment checklist — `gps-para-el-cielo`

Prepared 2026-11-22 from the working tree of branch
`chore/firebase-client-migration` (uncommitted). Nothing has been deployed,
committed, enabled or charged. Production has not been read.

Legend: ✅ verified locally · ⚠️ decision needed · ⛔ blocked on client /
Melissa · ❓ unverified (needs read access to production)

## 0. Local state (verified 2026-11-22)

| Item | State |
|---|---|
| 50 Rancho del Rey properties | ✅ served from the emulator cache: 50 records, 50 named, `complete`, after 3 emulator restarts and 3 app relaunches; round `r0` holds the same 50 |
| Backups | ✅ `.local-backups/pilot-20261122-153756` (+ `.tgz`), `post-migration-20261122-160630`: checksums OK; `pre-restarts-20261122-162638` (new export) |
| Melissa recordings | ✅ 55 files, identical to the backup |
| Git | ✅ `.emulator-data`, `.local-backups`, `functions/.melissa-recordings`, `functions/.secret.local`, `functions/.env.local` are git-ignored |
| Spending guard | ✅ tests: `test/no_network.js` blocks every non-local host; emulator: `guard.js` replay-only unless `MELISSA_EMULATOR_LIVE=true` (set nowhere); local discovery switch off; usage counters: 0 Melissa requests |
| Production switches | ✅ `functions/.env.gps-para-el-cielo`: `MELISSA_ALLOW_OWNER_NAMES=false`, `MELISSA_OWNER_DISCOVERY_ENABLED=false`, `MELISSA_OWNER_SHARED_CACHE=false`, `MELISSA_GAP_FILL_ENABLED=false`, `ENFORCE_APP_CHECK=false` |
| Tests | ✅ Flutter 447 (+1 old skip), functions 76/76, rules 21/21, analyzer clean |
| **Deploy upload** | ✅ **fixed 2026-11-22**: `firebase.json` functions `ignore` did not exclude `.melissa-recordings` (real owner names), `.secret.local`, `.env.local`, `tool/`. A deploy would have uploaded them to Google Cloud. Now the upload is only `src/` (9 files), `package.json`, `package-lock.json`, `.gitignore`, `.env.gps-para-el-cielo` (checked with the CLI's own file walker, locally) |

## 1. Functions in this repository

| Function | Type | Runtime service account | Uses secret |
|---|---|---|---|
| `enrichHousehold` | 2nd gen callable, us-central1, 256 MiB, max 5 | `1044715224614-compute@developer.gserviceaccount.com` | `MELISSA_CREDIT_LICENSE` |
| `discoverNearby` | 2nd gen callable, max 3 | same | same |
| `discoverOwners` | 2nd gen callable | same | same |
| `cleanupDeletedUser` | **1st gen** Auth `onDelete` | `gps-para-el-cielo@appspot.gserviceaccount.com` (App Engine default) | — |

✅ **Zero-credit first deployment (set 2026-11-22).**
`MELISSA_GLOBAL_DAILY_CREDITS=0` in `functions/.env.gps-para-el-cielo`. It is
now an **app-wide** daily cap over all three paid endpoints together
(`src/budget.js`: `credits` + `gapCredits` + `ownerCredits` on
`melissa_usage/{day}`), checked inside each endpoint's reservation
transaction before any Melissa request. 0, negative, missing or invalid →
every paid request refused (`app_daily_limit`); the param default is 0
(fail closed). Stored/cached answers are still served. Tests:
`functions/test/zero_budget.test.js`. When paid calls are approved, raise
it to at least the sum of the endpoint budgets you want to allow
(e.g. 150 address checks + 2,000 owner discovery = 2,150).

## 2. IAM roles for the developer account

Today the account has `roles/firebase.admin` only (covers Firestore rules
deploy). Needed in addition, on project `gps-para-el-cielo`:

| Role | Why |
|---|---|
| `roles/serviceusage.serviceUsageConsumer` | every CLI call (today's 403) |
| `roles/cloudfunctions.admin` | create / update the 4 functions |
| `roles/run.admin` | 2nd-gen functions are Cloud Run services; callables need public invoker |
| `roles/artifactregistry.admin` | CLI creates `gcf-artifacts` and its cleanup policy |
| `roles/cloudbuild.builds.editor` | read function builds and their logs |
| `roles/secretmanager.admin` | create `MELISSA_CREDIT_LICENSE`, add versions, grant the runtime access |
| `roles/iam.serviceAccountUser` **on** `1044715224614-compute@developer.gserviceaccount.com` | deploy 2nd-gen functions as that account |
| `roles/iam.serviceAccountUser` **on** `gps-para-el-cielo@appspot.gserviceaccount.com` | deploy the 1st-gen `cleanupDeletedUser` |

Alternative: project **Owner** (simplest, broader).

If the client enables the APIs first (§3), `serviceUsageConsumer` is
enough; otherwise `roles/serviceusage.serviceUsageAdmin` lets the CLI
enable them itself.

Service accounts (client grants, ❓ defaults may already cover them):

| Account | Role | Why |
|---|---|---|
| `1044715224614-compute@…` | `roles/cloudbuild.builds.builder`, `roles/logging.logWriter`, `roles/artifactregistry.writer` | Cloud Build runs as this account in newer projects |
| `1044715224614-compute@…` | `roles/datastore.user` | functions read/write Firestore (often covered by default Editor) |
| `gps-para-el-cielo@appspot…` | `roles/datastore.user` | `cleanupDeletedUser` deletes user data |

❓ If the App Engine default service account does not exist, the 1st-gen
deploy fails. Options: deploy the other three first (`--only
functions:enrichHousehold,functions:discoverNearby,functions:discoverOwners`)
and decide later; account deletion in the app already deletes the user's own
data client-side.

## 3. Google Cloud APIs

| API | Needed for | State |
|---|---|---|
| `firestore.googleapis.com` | database | ✅ in use (Firestore `nam5` exists) |
| `identitytoolkit.googleapis.com` | Firebase Auth | ✅ in use (app signs in) |
| `firebaserules.googleapis.com` | rules deploy | ❓ likely on (Firebase project) |
| `serviceusage.googleapis.com`, `cloudresourcemanager.googleapis.com` | CLI | ❓ normally on by default |
| `cloudfunctions.googleapis.com` | all functions | ❓ required |
| `cloudbuild.googleapis.com` | builds | ❓ required |
| `artifactregistry.googleapis.com` | images | ❓ required |
| `run.googleapis.com` | 2nd gen | ❓ required |
| `secretmanager.googleapis.com` | Melissa key | ❓ required |
| `cloudbilling.googleapis.com` | CLI billing check | ❓ usually on |
| `eventarc.googleapis.com`, `pubsub.googleapis.com` | not needed by the current functions (callables + 1st-gen Auth trigger) | optional |
| `firebaseappcheck.googleapis.com` | only when `ENFORCE_APP_CHECK=true` | optional, later |

"❓" = cannot be checked: the account lacks `serviceusage.services.list`.
After access is granted, read-only check:
`gcloud services list --enabled --project gps-para-el-cielo`.

## 4. Secret Manager

| Who | Permission | Role |
|---|---|---|
| Developer | `secrets.create`, `versions.add` (`firebase functions:secrets:set`), `secrets.get` / `versions.get` (deploy validation), `secrets.getIamPolicy` / `setIamPolicy` (CLI grants runtime access) | `roles/secretmanager.admin` |
| Runtime `1044715224614-compute@…` | `versions.access` on `MELISSA_CREDIT_LICENSE` only | `roles/secretmanager.secretAccessor` (granted by the CLI at deploy) |
| 1st-gen account | none | — |

The key is typed at the `secrets:set` prompt, never stored in the repo.
Functions referencing a secret cannot deploy until the secret exists.

## 5. Firestore rules: review and read-only check

Repository `firestore.rules` vs `master`: **additive only**. It adds
`prayerIntention` to the allowed profile fields and new private
subcollections (`enrichment`, `gap_areas`, `prayer_log`, `prayer_rounds`),
and denies client access to server collections (`owner_*`,
`discovery_jobs`, `melissa_usage`), which were already denied by default.
Older app versions keep working.

❓ The rules **actually live** on `gps-para-el-cielo` are unknown (the client
project may hold rules other than `master`). Do not deploy before step 2.

Read-only procedure (only after your explicit approval):

1. Save the live rules: Firebase console → Firestore → Rules → copy into
   `.local-backups/prod-rules-<date>.rules` (or Rules API
   `projects.releases.get` + `rulesets.get`, both read-only).
2. `diff` it with `firestore.rules`; anything in production not in the
   repository is merged into the repository first and covered by a test.
3. Run the repository rules tests against the merged file (local emulator).
4. Data check, read-only (reads all `users` docs and their
   `household_status`, `prayer_log`, `prayer_rounds`; prints field names
   and counts only, never values):
   `cd functions && GOOGLE_APPLICATION_CREDENTIALS=… node tool/check_rules_compat.js gps-para-el-cielo --read-production`
   Exit 0 = every document can still be updated; any `BLOCKS UPDATES`
   line = fix the rules or data first. Cost: one read per document.
5. Keep the saved file as the rollback ruleset.

## 6. Costs beyond Firebase Blaze usage

Estimates; check current Google pricing pages before approval.

| Item | Expected at this volume |
|---|---|
| **Melissa credits** | the real cost; separate Melissa billing; 0 while switches are off and `MELISSA_GLOBAL_DAILY_CREDITS=0` |
| Cloud Run / Functions invocations, CPU, memory | within monthly free tier; no minimum instances, so no idle cost |
| Cloud Build | per deploy; normally within the free build minutes |
| Artifact Registry | container images; ~0.5 GB free, then per GB-month. Set the cleanup policy the CLI offers (e.g. keep 1 day) |
| Cloud Storage | function source archives; small |
| Secret Manager | 1 secret, few versions; within or near the free tier (per active version / per 10k accesses) |
| Cloud Logging | within the 50 GiB/month free allotment |
| Firestore | reads/writes per `docs/COST_MODEL.md` §4 |
| Outbound network to Melissa | negligible |

## 7. Melissa licensing vs technical deployment

**Technical (needs client IAM / APIs only):** rules deploy, secret,
functions deploy with every Melissa switch off, app release without
`MELISSA_OWNERS` / `ADDRESS_CHECKS`. Zero Melissa credits; no owner names.

**Melissa written licence (needed before turning on, not before deploying):**

| Switch | Needs |
|---|---|
| `MELISSA_ALLOW_OWNER_NAMES=true`, app `MELISSA_OWNERS=true` | display of recorded owner names to app users |
| `MELISSA_CACHE_DAYS` | how long owner records may be stored |
| `MELISSA_OWNER_SHARED_CACHE=true` | one stored record shown to several users |
| `MELISSA_OWNER_NEGATIVE_CACHE_DAYS` | storing "no match" facts |
| `MELISSA_OWNER_DISCOVERY_ENABLED=true`, `MELISSA_GLOBAL_DAILY_CREDITS>0`, `MELISSA_GAP_FILL_ENABLED=true` | client spending approval + budgets |

The local pilot data (real owner names) is never uploaded to production.

## 8. Deployment order (after approvals)

0. Commit the reviewed working tree (with approval) and deploy from that
   commit; re-run `flutter test`, functions tests, rules tests; re-run the
   upload check (`firebase.json` ignore list).
1. Client grants §2 roles and enables §3 APIs. Verify read-only:
   `gcloud services list --enabled`, `gcloud projects get-iam-policy`.
2. §5 read-only rules and data check (approved separately).
3. **Rules only:** `firebase deploy --only firestore:rules --project gps-para-el-cielo`.
   Check the current app still signs in, reads and prays. Rollback: re-publish
   the saved ruleset.
4. **Secret:** `firebase functions:secrets:set MELISSA_CREDIT_LICENSE --project gps-para-el-cielo`.
5. **Functions, all spending off** (`MELISSA_GLOBAL_DAILY_CREDITS=0` unless
   address checks are approved):
   `firebase deploy --only functions --project gps-para-el-cielo`.
   Never a bare `firebase deploy` (it would also deploy hosting and indexes).
   Smoke test: `discoverOwners` → `owner_names_disabled`;
   `enrichHousehold` → `app_daily_limit`; `melissa_usage` stays empty;
   delete a throwaway test account → its `users/{uid}` disappears.
6. **App release** (staged rollout) built without `MELISSA_OWNERS` and
   `ADDRESS_CHECKS`. It works with both old and new rules.
7. **After the Melissa licence and spending approval:** set the switches in
   `functions/.env.gps-para-el-cielo`, redeploy functions, then an app build
   with `--dart-define=MELISSA_OWNERS=true`.

Rollback at any step: previous ruleset; `firebase functions:delete <name>`
or redeploy the previous commit; app: halt the staged rollout.

## Cutover record — 2026-11-23 (gps-para-el-cielo)

- **Firestore rules** deployed (ruleset `bcaf80a0-c045-45a6-b44b-d58c460a9cd8`, identical to `firestore.rules`).
  Previous ruleset kept for rollback: `632b077d-202e-457f-ba7c-e9da1b44a13d`
  (re-release it in the console, or deploy `.local-backups/prod-backup-20261123-100945/firestore.rules.live`).
  Compatibility: `tool/firestore_rules_test/prod_compat.js` on a read-only backup of every production
  user document — everything the old rules allowed still works; prayer_log / prayer_rounds (denied before) now work;
  cross-user reads and owner_* reads stay denied. Rules suite 21/21. Indexes unchanged (identical).
- **Functions** deployed: discoverOwners, discoverNearby, enrichHousehold (2nd gen, ACTIVE),
  cleanupDeletedUser (1st gen, ACTIVE; first build failed on a missing gcf-artifacts repo, retry passed).
  Artifact cleanup policy: images older than 1 day.
- **Paid Melissa off**: MELISSA_GLOBAL_DAILY_CREDITS=0, discovery / gap-fill / owner names / shared cache false.
  Key only in Secret Manager (version 1); runtime account has secretAccessor on that one secret.
- **Owner records NOT migrated**: no written Melissa licence for storage + multi-user display.
  Ready: `functions/tool/migrate_pilot.js plan|apply|verify|rollback` (snapshot expires 2026-12-22).
- **Local backups** (git-ignored, mode 600): `.local-backups/prod-backup-20261123-100945` (live rules, ruleset, indexes, all non-cell documents).
