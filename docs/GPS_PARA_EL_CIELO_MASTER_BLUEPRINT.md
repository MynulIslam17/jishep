# GPS PARA EL CIELO — Master Blueprint

**The single source of truth for this application.** It describes the app
**as it actually exists**, says plainly what is local, deployed, blocked or
planned, and links to the detailed documents. Every significant code change
must update the relevant section, diagram and tests.

| | |
|---|---|
| Last updated | 2026-11-24 |
| Code baseline | `master` @ `0f4bf97` (v1.0.1) + the 2026-11-24 changes (uncommitted at time of writing) |
| Production | Firebase `gps-para-el-cielo` (rollback: `gps-cielo`; `cielo-63925` must never be touched) |
| Client | Global Alliance of Christian Churches, Inc. (gaccchurch.org) |
| Owner decisions 2026-11-24 | UI: **targeted** (keep the approved design) · Production: **local only** (nothing deployed) · Live Melissa: **keep OFF** (credits insufficient) |

### Document index

| Document | Covers |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | components, data model, location model, environments |
| [APP_FLOW.md](APP_FLOW.md) | user journey, screen-by-screen behaviour (current + history) |
| [CACHE_DESIGN.md](CACHE_DESIGN.md) | Firestore cache, 365-day lifecycle, migration |
| [GEOSPATIAL_ALGORITHMS.md](GEOSPATIAL_ALGORITHMS.md) | geohash, nearest-K, coverage, complexity |
| [MELISSA_COST_CONTROL.md](MELISSA_COST_CONTROL.md) | Melissa products, credits, budgets, kill switch, reporting |
| [UI_UX_DESIGN_SYSTEM.md](UI_UX_DESIGN_SYSTEM.md) | tokens, components, screens, accessibility |
| [SECURITY.md](SECURITY.md) | auth, rules, App Check, location authority, threats |
| [PRODUCTION_DEPLOYMENT.md](PRODUCTION_DEPLOYMENT.md) | rollout, rollback, live-Melissa activation, release log |
| [TESTING_STRATEGY.md](TESTING_STRATEGY.md) | suites, counts, edge-case coverage |
| [INCIDENT_RESPONSE.md](INCIDENT_RESPONSE.md) | runbooks with exact commands |
| [APP_CHECK.md](APP_CHECK.md) | App Check implementation, console steps, enforcement plan |
| [MIGRATION_365_CHECKLIST.md](MIGRATION_365_CHECKLIST.md) | 365-day migration + deploy verification (53 records) |
| [COMPATIBILITY_AUDIT.md](COMPATIBILITY_AUDIT.md) | installed 1.0.0 builds vs the new backend |
| [diagrams/](diagrams/README.md) | the 15 architecture diagrams (rendered SVGs in diagrams/rendered/) |
| Older, still valid in part | [NATIONWIDE_CELLS.md](NATIONWIDE_CELLS.md), [MELISSA_FIRST.md](MELISSA_FIRST.md), [NEIGHBORS_FEATURE_SPEC.md](NEIGHBORS_FEATURE_SPEC.md), [push_notifications.md](push_notifications.md), [store_release.md](store_release.md), [store_privacy.md](store_privacy.md) |

---

## 1. Product vision

A calm, simple app that helps church members pray for the households around
their home, one neighborhood at a time, and follow up with visits and
invitations — for US neighborhoods, Spanish-speaking congregations first.

## 2. Application goals

1. Every user has one primary neighborhood, chosen at signup.
2. The nearest homes (up to 50, never invented) are shown with a recorded
   owner name where one is legitimately stored.
3. Paid property data is bought once and reused by everyone and every
   overlapping neighborhood; nothing is paid for twice.
4. Prayer progress is private, persistent and survives devices, reinstalls
   and data refreshes.
5. Spending is bounded, observable and can be stopped instantly.

## 3. User roles

| Role | Can | How |
|---|---|---|
| User | set the primary location once, pray, follow up, edit profile and preferences, contact support, delete account | the app |
| Support / operator | correct a user's primary location (audited), stop paid lookups, read usage reports, run migrations | `functions/tool/*.js` with their own Google credentials (ADC); no admin UI, no callable |
| Project owner | approve deploys, budgets, paid tests | — |

## 4. Feature inventory and audit (Part 1)

Status codes: **1** production-verified · **2** implemented, locally tested ·
**3** partial · **4** missing · **5** broken · **6** security risk ·
**7** needs configuration/credentials · **8** needs migration · **9** needs
deployment.

| Feature | Status | Evidence |
|---|---|---|
| Canonical property cache `owner_properties/mel:{MAK}` + `owner_scans` | 1 (deployed 2026-11-23; 53 docs imported, verified identical) | `functions/src/property_cache.js`; `tool/enable_owner_names.sh` |
| Overlapping-area reuse, dedupe by MAK, parcel dedupe | 2 (code deployed; prod has one area) | `serveFromCache`; `functions/test/pilot.test.js`, `blueprint.test.js` (2 and 5 overlapping scans) |
| Partial / complete coverage classification | 2 | `coveredRadius`, completeness states; `owners.test.js` |
| One paid job per area (lease), resumable discovery | 2 (paid OFF in prod) | `acquireLease`; "100 simultaneous users → ONE paid discovery" |
| Budget guards (request, user, day, month, app-wide) | 1 for budget 0 (prod), 2 otherwise | `reserveOwners`, `budget.js`; `zero_budget.test.js` |
| Cache-only mode | 1 (prod mode) | `MELISSA_OWNER_DISCOVERY_ENABLED=false` |
| Prayer history preservation (log, rounds) | 1 (rules deployed 2026-11-23) | `prayer_log`, `prayer_rounds`; `test/prayer_history_test.dart` |
| **Signup-only location; client lock in rules** | 2 · 9 | `firestore.rules` `locationChangeAllowed`; rules tests |
| **Location controls removed from the app** | 2 (needs an app release) | `test/fixed_location_test.dart` |
| **Server-authoritative location (`primary_locations`)** | 2 · 9 | `owners.js` `primaryLocation`; `blueprint.test.js` |
| **Admin-authorized correction (audited, rate-limited)** | 2 | `functions/src/location.js`, `tool/location_admin.js`; `ops_tools.test.js` |
| **365-day cache** | 2 · 8 · 9 (local migration rehearsed: all 53 at 365 days) | `MELISSA_CACHE_DAYS=365`; `tool/migrate_cache_ttl.js` |
| **Kill switch** | 2 · 9 | `budget.js` `paidDisabled`; `tool/melissa_ops.js kill` |
| **Verified-account gate for paid discovery** | 2 · 9 | `isVerifiedToken`; `blueprint.test.js` |
| **Budget-limited answers return stored data (no throw)** | 2 · 9 | `owners.js`; `owners.test.js` limits test |
| **Usage report + threshold warnings** | 2 (CLI); no dashboards/alerts | `tool/melissa_ops.js report` |
| App Check | **2 (local)** — `firebase_app_check` in the app (Play Integrity / DeviceCheck), soft server gate on paid lookups; **4 · 7** console registration, release and deploy pending; hard enforcement off | [APP_CHECK.md](APP_CHECK.md) |
| Live Melissa discovery in production | **7 — BLOCKED on approval + App Check** (not on credits): balance **10,250 credits**, Auto-Refill off (2026-11-24) ≈ 11–14 new areas at ~700–920 each | §15 |
| Personator (resident names) | not available — GE08 on both keys (2026-11-23); not used | [MELISSA_COST_CONTROL.md](MELISSA_COST_CONTROL.md) |
| Monitoring / alerting | 3 — structured logs (counts only) + CLI report; no Cloud Monitoring alerts | §24 |
| Account-deletion cleanup of per-user locks | was **5** (query never matched) → fixed, 2 · 9 | `functions/src/cleanup.js`; `blueprint.test.js` |
| About screen version | was **5** (showed 1.0.0) → fixed, 2 | `test/about_credit_test.dart` |
| Load test at 1,000 users | 4 (100 concurrent tested) | [TESTING_STRATEGY.md](TESTING_STRATEGY.md) |
| Dark mode, Spanish UI | 4 | [UI_UX_DESIGN_SYSTEM.md](UI_UX_DESIGN_SYSTEM.md) §8 |

## 5. Screen-by-screen specification

See [UI_UX_DESIGN_SYSTEM.md §5](UI_UX_DESIGN_SYSTEM.md#5-screen-specifications-what-changed-2026-11-24-in-bold).
Summary of 2026-11-24 changes: no screen can change the location; Profile
shows "Your neighborhood" read-only with Contact support; setup warns that
the choice is lasting; empty/unavailable states offer Contact support.

## 6. Navigation architecture

Splash → Onboarding → Sign in / Sign up → Verify email (password accounts)
→ Location setup (only without a saved location) → bottom tabs Home ·
Neighborhood · Prayer List · Follow-up · Profile. `lib/routes/app_pages.dart`;
[diagram 02](diagrams/02_signup_authentication.md).

## 7. Signup and location policy

- Chosen once during setup (address search or GPS, map pin, nearby preview
  from free Overture data only — no paid call while typing, dragging or on
  map movement).
- Saved to `users/{uid}` with `locationConfirmedAt` / `locationVersion`.
- Locked for the client by the rules; the server uses its own pinned copy
  (`primary_locations/{uid}`), so deleting and re-creating the profile does
  not move it.
- Corrections: support only (`tool/location_admin.js correct`, ≤ 2 per user
  per 365 days, audited). A correction buys nothing by itself.
- Existing users: saved coordinates are their primary location; missing →
  setup. No forced re-signup, no data deleted.
Details: [ARCHITECTURE.md §3](ARCHITECTURE.md#3-location-model-blueprint-21),
[diagram 03](diagrams/03_primary_location_onboarding.md).

## 8. Authentication

Email/password (verification required before recording activity), Google,
Sign in with Apple, phone OTP for existing accounts. Profiles are keyed by
uid, so logout, reinstall, new device and provider linking reuse the same
data and the same server cache: none of them triggers a paid lookup.

## 9. Household discovery architecture

Overture-first: the homes come from free Overture address cells
(`cells/{geohash}`); `discoverOwners` adds recorded owners from the shared
Melissa cache, matched by street address (`OwnerOverlayArea`). Paid discovery
(when ever enabled) is cache-first, lease-protected and budgeted.
[diagram 04](diagrams/04_cache_first_discovery.md).

## 10. Melissa integration

Reverse GeoCoder (nearby deliverable addresses, ~2 credits per address
returned) + Property LookupProperty by MAK (~9 credits, recorded owner).
Keys only in Secret Manager (`MELISSA_CREDIT_LICENSE`) and
`~/.config/gps-cielo/melissa.env` locally; never in the app or logs.
Emulator: replay-only (`functions/src/guard.js`). Products/prices verified
2026-11-21; Personator unavailable.
[MELISSA_COST_CONTROL.md](MELISSA_COST_CONTROL.md).

## 11. Geospatial indexing

Geohash (precision 5 for scan lookup with neighbour expansion, 9 stored on
properties, 6 for discovery locks). H3 evaluated and not adopted (no new
dependency; geohash meets the need).
[GEOSPATIAL_ALGORITHMS.md](GEOSPATIAL_ALGORITHMS.md),
[diagram 05](diagrams/05_overlap_cache_reuse.md).

## 12. Cache-first algorithm

```
discoverOwners(uid, data):
  require owner names allowed, signed in, cacheDays > 0
  home = primary_locations/{uid} (pin from users/{uid} on first use)
  if client sent a point farther than 250 m from home: refuse (location_not_authorized)
  served = serveFromCache(home)            # scans near home → dedupe → nearest-first → coverage
  if served complete/empty: return it      # 0 credits
  plan = planMissing(served)               # scan here? which lookups?
  if discovery disabled or nothing to buy: return served + missing
  if unverified or kill switch on: return served + limited
  lease discovery_jobs/{scope}_{geohash6}; else wait for the holder and return
  re-read cache and re-plan (double check)
  reserve estimated credits (request/user/day/month/app-wide); on limit: return served + limited
  Reverse GeoCoder (if needed) → store scan; Property lookups nearest-first → store each answer
  settle (return unused credits); release lease; return fresh serve
```
Real code: `functions/src/owners.js` `discoverOwners`.

## 13. Firestore data model

[ARCHITECTURE.md §2](ARCHITECTURE.md#2-firestore-data-model),
[diagram 06](diagrams/06_firestore_data_model.md).

## 14. 365-day caching lifecycle

Fresh for `MELISSA_CACHE_DAYS=365` (named owners, scans) and
`MELISSA_OWNER_NEGATIVE_CACHE_DAYS=365` (exclusions — as long as the scans,
so an excluded address is never bought twice).
**Expiry never deletes**: a stale record is not served as fresh and is kept;
refresh happens only through an authorized, budgeted paid discovery. The
existing records are extended by `tool/migrate_cache_ttl.js` (backup →
apply with update-time preconditions → verify → rollback). Rehearsed on the
local emulator 2026-11-24: all 53 records (50 named, 2 negative, 1 scan)
extended and verified; re-run changes nothing. Production: **not run** (prod records currently expire
2026-12-22 — deploy before then or they stop being served).
[CACHE_DESIGN.md](CACHE_DESIGN.md), [diagram 13](diagrams/13_expiry_refresh.md).

## 15. Credit budgeting

| Layer | Setting | Production file value |
|---|---|---|
| App-wide daily (all endpoints) | `MELISSA_GLOBAL_DAILY_CREDITS` | **0** (no paid call possible) |
| Paid discovery switch | `MELISSA_OWNER_DISCOVERY_ENABLED` | **false** |
| Per request | `MELISSA_OWNER_REQUEST_MAX_CREDITS` | 920 |
| Per user per day | `MELISSA_OWNER_PER_USER_DAILY` | 5 |
| Owner discovery per day / month | `MELISSA_OWNER_DAILY_CREDITS` / `_MONTHLY_CREDITS` | 2,000 / 20,000 |
| Kill switch | `melissa_usage/state.paidDisabled` | off (tool: `melissa_ops.js kill`) |
| Verified accounts only | `MELISSA_OWNER_REQUIRE_VERIFIED` | true (not deployed) |

**Live activation is blocked** on the owner's approval and App Check (no
longer on credits): real spend to date ≈ 704 credits; balance **10,250
credits**, Auto-Refill off (Melissa dashboard, 2026-11-24); one new 50-home
area costs ≈ 700–920. No paid call was made on 2026-11-24. The activation
procedure is in [PRODUCTION_DEPLOYMENT.md](PRODUCTION_DEPLOYMENT.md).
[MELISSA_COST_CONTROL.md](MELISSA_COST_CONTROL.md),
[diagram 07](diagrams/07_credit_accounting.md).

## 16. Security model

Auth on every callable; rules restrict every client write to known fields;
shared Melissa collections, locks, counters, `primary_locations` and
`location_corrections` are server-only; location authority on the server;
secrets in Secret Manager; logs carry counts only. **Open blocker: App Check**
is implemented locally (client + soft gate) but not registered in the
consoles, released or deployed; required before any paid discovery is
enabled ([APP_CHECK.md](APP_CHECK.md)). [SECURITY.md](SECURITY.md),
[diagram 11](diagrams/11_app_check_authorization.md).

## 17. User prayer activity

Private under `users/{uid}`: `household_status` (prayed, visited, invited,
follow-up, notes, private name), `prayer_log` (append-only), `prayer_rounds`
(fixed membership). Never shared, never touched by cache refreshes or
location corrections. [diagram 10](diagrams/10_household_identity.md).

## 18. Follow-up lifecycle

Visited / invited / follow-up date / notes on `household_status`; the
Follow-up tab pages through them (`follow_up_controller.dart`); preserved
across rounds and corrections. [diagram 09](diagrams/09_prayer_list_lifecycle.md).

## 19. Offline behaviour

Firestore's offline cache keeps profile, statuses and history; writes queue
and sync. Overture cells already read are cached by Firestore. Owner names
need the callable: offline, homes show their address. No paid call is ever
triggered by reconnecting.

## 20. Error handling

Server reasons → plain sentences (`OwnerDiscoveryService.messageFor`);
budget limits return stored data with `limited`; transient errors are
retried only by the user (pull to refresh); Melissa errors are classified
charged/uncharged; STOP errors (out of credits, licence) halt the job and
pause paid lookups. [diagram 12](diagrams/12_failure_recovery.md).

## 21. Testing standards

Emulator/mocks only; tests cannot reach the network (`test/no_network.js`).
Current counts: functions **121**, rules **25**, Flutter **457**, all
passing (2026-11-24). [TESTING_STRATEGY.md](TESTING_STRATEGY.md).

## 22. Performance requirements

Bounded reads per request (scan lookup by ≤ 30-cell `in` queries + chunked
`getAll` of ≤ 60 properties until K named), no dataset loaded into memory,
callable 120 s timeout / 256 MiB / max 5 instances. Benchmarks:
[performance/](performance/). Complexity:
[GEOSPATIAL_ALGORITHMS.md](GEOSPATIAL_ALGORITHMS.md).

## 23. Production deployment

`tool/deploy_blueprint.sh --approve=gps-para-el-cielo` — prepared, **not
run**. Backend and mobile releases are separate (Codemagic → TestFlight /
Play). [PRODUCTION_DEPLOYMENT.md](PRODUCTION_DEPLOYMENT.md),
[diagram 14](diagrams/14_production_deployment.md).

## 24. Monitoring and alerting

Today: structured function logs (outcome, counts, credits; no uid, address
or name), `melissa_usage` counters, `tool/melissa_ops.js report` with
80 %-threshold warnings, the Melissa portal balance. Missing: Cloud
Monitoring alert policies and a dashboard (planned).
[diagram 15](diagrams/15_monitoring_incident.md).

## 25. Backup and rollback

Local: `tool/emulators.sh` export every 10 min; `.local-backups/`
(git-ignored) holds the pilot, migration and 2026-11-24 pre-TTL backups.
Production: rules history, per-step rollback commands, TTL backup files.
[PRODUCTION_DEPLOYMENT.md](PRODUCTION_DEPLOYMENT.md).

## 26. Risks and limitations

| Risk | Status / mitigation |
|---|---|
| App Check not enforced → scripted calls with real accounts | budgets, verified gate, server location, global caps; **enforce before paid** |
| Melissa licence: no written agreement; owner names shown on the project owner's authority (2026-11-23); Data Products terms mention rental / no third-party display; 365-day storage chosen by the owner | owner's decision, recorded; revisit with Melissa |
| Recorded owner ≠ resident (22 of 50 pilot owners are trusts/companies) | labelled "Property Owner (Public Record)", never "resident" |
| Credits insufficient for live discovery | blocked, see §15 |
| Production cache expires 2026-12-22 unless the 365-day migration is deployed | deploy script step 5 |
| Old app (1.0.0/1.0.1) after the new rules: its "My address" editor will fail with an error | expected; the new build removes it |
| Overture coverage limited to imported states | `AppStrings.areasAvailable`; [NATIONWIDE_CELLS.md](NATIONWIDE_CELLS.md) |

## 27. Known technical debt

App Check; alerting; 1,000-user load test; dark mode; Spanish UI;
`UserRepository.updateLocation` kept only for tests; legacy `owner_areas`
and `households` demo data (`demo_bd_*`, remove before real use); blueprint
completeness names differ from code names (see
[CACHE_DESIGN.md](CACHE_DESIGN.md)).

## 28. Environment variable reference

All in `functions/.env.gps-para-el-cielo` (not secret, tracked) and
`functions/.env.local` (emulator, git-ignored); defaults in
`functions/src/index.js`. Full table with defaults and production values:
[MELISSA_COST_CONTROL.md](MELISSA_COST_CONTROL.md) and
[ARCHITECTURE.md §8](ARCHITECTURE.md#8-environments-and-switches). New on
2026-11-24: `MELISSA_CACHE_DAYS=365` (default 365),
`MELISSA_OWNER_LOCATION_TOLERANCE_M=250`, `MELISSA_OWNER_REQUIRE_VERIFIED=true`.

## 29. Operational runbooks

| Task | Command (from `functions/`) |
|---|---|
| Stop all paid Melissa calls now | `node tool/melissa_ops.js kill --project=gps-para-el-cielo --reason="…" --approve=gps-para-el-cielo` |
| Usage report | `node tool/melissa_ops.js report --project=gps-para-el-cielo --days=30` |
| Location status (counts) | `node tool/location_admin.js status --project=gps-para-el-cielo` |
| Correct one user's location | `node tool/location_admin.js correct --project=… --uid=… --lat=… --lon=… --address="…" --reason="…" --operator="…" --approve=…` |
| 365-day migration | `node tool/migrate_cache_ttl.js plan|backup|apply|verify|rollback …` |
| Local emulators | `tool/emulators.sh` (repo root) |
More: [INCIDENT_RESPONSE.md](INCIDENT_RESPONSE.md).

## 30. Roadmap

1. **Approve and run** `tool/deploy_blueprint.sh` (before 2026-12-22).
2. Release an app build with the fixed-location UI (Codemagic → TestFlight /
   Play), after step 1.
3. App Check: console steps in [APP_CHECK.md](APP_CHECK.md) §3 (DeviceCheck
   key, Play Integrity + fingerprints), release the App Check build, then
   hard enforcement only after old builds are retired.
4. Buy Melissa credits; confirm terms; then the bounded one-area live test
   ([PRODUCTION_DEPLOYMENT.md](PRODUCTION_DEPLOYMENT.md)).
5. Cloud Monitoring alerts on spend and errors.
6. Spanish localisation; dark mode; accessibility pass.
7. Remove demo households; import more Overture states.
