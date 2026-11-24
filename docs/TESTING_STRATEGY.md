# Testing strategy — GPS PARA EL CIELO

Blueprint §21. Every test uses mocks, fixtures or the local Firebase
emulators. **No test can reach the internet or spend Melissa credits.**

## 1. Suites and counts (verified 2026-11-24)

| Suite | Location | Tests | Result |
|---|---|---|---|
| Cloud Functions (Firestore emulator) | `functions/test/*.test.js` | 121 | 121 pass |
| Firestore rules | `tool/firestore_rules_test/rules.test.js` | 25 | 25 pass |
| Flutter unit + widget | `test/**/*_test.dart` | 457 (+1 skipped) | all pass |
| Flutter analyzer | `flutter analyze` | — | no issues |
| Integration (device/emulator) | `integration_test/owner_names_flow_test.dart` | — | not run in this pass |

Functions per file: blueprint 21, cache_geo 7, discover 14, enrich 16,
melissa 15, migrate_pilot 8, ops_tools 6, owners 18, pilot 6, zero_budget 10.

## 2. How to run

```sh
# Java 21 for the emulators
export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
export PATH="$JAVA_HOME/bin:$PATH"

# Functions — own emulator (fails if port 8080 is taken)
cd functions && npm test
# Functions — against an already running emulator (e.g. tool/emulators.sh)
cd functions && npm run test:local     # FIRESTORE_EMULATOR_HOST=127.0.0.1:8080
# Uses project id demo-gps-cielo-functions: separate data from the dev
# emulator's gps-para-el-cielo namespace.

# Rules
cd tool/firestore_rules_test && npm test
#   or against a running emulator:
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node --test rules.test.js

# Flutter
flutter analyze && flutter test
```

CI: Codemagic `flutter-ci` runs `flutter analyze --no-fatal-infos` and
`flutter test`. Functions and rules suites run locally (need Java).

## 3. No-network guarantee

- `functions/test/no_network.js` (required by every functions run) makes
  any fetch to a non-local host throw; `cache_geo.test.js` asserts it.
- `guard.js`: in the Functions emulator Melissa is replay-only
  (`functions/.melissa-recordings`); unrecorded requests are refused
  without network unless `MELISSA_EMULATOR_LIVE=true` (never set).
- Fake Melissa functions count calls; tests assert `calls.length === 0`
  wherever no spend is allowed. Owner names in fixtures say `TEST`.
- Paid Melissa load tests are forbidden.

## 4. What each area covers

| Area | Tests |
|---|---|
| Cache hits / misses, overlap reuse, dedupe, nearest-K, completeness | `owners.test.js`, `blueprint.test.js`, `pilot.test.js`, `cache_geo.test.js` |
| 365-day TTL and migration | `blueprint.test.js` (365-day freshness), `ops_tools.test.js` (TTL plan/backup/apply/verify/rollback) |
| Budgets, kill switch, zero-budget production | `zero_budget.test.js`, `owners.test.js` (limits), `blueprint.test.js` (kill switch, farming cap) |
| Location authority + lock | `blueprint.test.js` (location authority ×3, location lock, concurrent pin), `rules.test.js` (primary location ×4) |
| Verified gate | `blueprint.test.js` |
| Concurrency / leases | `owners.test.js` (100 simultaneous users → 1 paid discovery; crashed lease), `blueprint.test.js` (expired lease) |
| Account deletion | `cache_geo.test.js`, `blueprint.test.js` (incl. discovery-job prefix fix) |
| Melissa parsing, retries, timeouts | `melissa.test.js`, `discover.test.js`, `enrich.test.js` (real saved responses for public buildings) |
| Operator tools + prod write guard | `ops_tools.test.js` |
| Fixed-location UI | `test/fixed_location_test.dart`, `test/home_screen_test.dart`, `test/location_setup_test.dart` |
| Server reason → user message | `test/owner_discovery_test.dart` (blueprint group) |
| Prayer list, rounds, history, follow-ups | `prayer_round_test.dart`, `prayer_history_test.dart`, `follow_up_paging_test.dart`, `prayer_progress_card_test.dart` |
| Auth flows | `auth_controllers_test.dart`, `auth_service_test.dart`, `verify_email_flow_test.dart`, `apple_*_test.dart`, `logout_loading_test.dart`, `account_cleanup_and_switch_test.dart` |

## 5. Blueprint §5.6 edge cases → coverage

| # | Case | Covered by |
|---|---|---|
| 1 | identical coordinates | `pilot.test.js` scenario A; `owners.test.js` "same user again is free" |
| 2 | 1 m apart | `blueprint.test.js` "A/B 1 m apart" |
| 3 | geohash boundary | `blueprint.test.js` "geohash boundary"; `pilot.test.js` G; `cache_geo.test.js` |
| 4 | overlaps two scans | `blueprint.test.js` "B overlaps two cached scans" |
| 5 | overlaps five scans | `blueprint.test.js` "B overlaps five cached scans" |
| 6 | duplicate MAKs across scans | `blueprint.test.js` (two scans, 20 shared MAKs); `pilot.test.js` I |
| 7 | multi-unit building | `blueprint.test.js` "multi-unit buildings and suites are skipped" |
| 8 | multiple owners | `blueprint.test.js` (second owner kept) |
| 9 | different properties, similar coordinates | partial: parcel dedupe (`property_cache` `duplicateParcel`) exercised in `owners.test.js`; no dedicated test |
| 10 | invalid cached address | partial: `owners.test.js` mismatch / not-found negatives; no corrupt-document test |
| 11 | partially expired cache | partial: `owners.test.js` expired cache, `blueprint.test.js` 365-day; mixed fresh/expired in one area not explicit |
| 12 | homes without owner names | `blueprint.test.js` (`noOwner`), `owners.test.js` |
| 13 | scan with only 15 valid homes | `blueprint.test.js` "only 15 valid homes" |
| 14 | commercial properties | `owners.test.js` REAL responses (federal building non-residential) |
| 15 | apartments / multi-family | `blueprint.test.js` multi-unit; `owners.test.js` classification |
| 16 | few properties | `owners.test.js` "never invents" |
| 17 | Melissa duplicate addresses | `discover.test.js` "parse: dedupes" |
| 18 | empty response | `blueprint.test.js` "Melissa empty / timeout / rate-limited" |
| 19 | unexpected response code | `melissa.test.js` transmission errors, 401 final |
| 20 | timeout | `melissa.test.js` "a slow Melissa times out"; `blueprint.test.js` |
| 21 | rate limit | `melissa.test.js` 429 retries; `blueprint.test.js` |
| 22 | paid discovery partially completes | `owners.test.js` "a crash part-way", out of credits |
| 23 | function restarts mid-job | `owners.test.js` crashed lease; `blueprint.test.js` expired lease |
| 24 | user closes app during discovery | server-side job continues/lease expires (same tests as 23); no client test |
| 25 | same user retries | `blueprint.test.js` "retry after partial progress never pays twice" |
| 26 | many users, same area | `owners.test.js` 100 simultaneous users → one discovery |
| 27 | cache expires during a request | **not covered** |
| 28 | insufficient credits | `owners.test.js` out of credits; `enrich.test.js` GE14 |
| 29 | daily/monthly budget exhausted | `owners.test.js` limits; `blueprint.test.js` budget exhausted |
| 30 | malicious arbitrary coordinates | `blueprint.test.js` location authority, location lock |
| 31 | account deleted during discovery | partial: cleanup tested; concurrent delete+discovery **not covered** |
| 32 | migration during normal requests | partial: TTL apply skips documents changed after backup (`ops_tools.test.js`) |
| 33 | old app version calls backend | `blueprint.test.js` old app sends saved coordinates; legacy cache test |
| 34 | Firestore unavailable | **not covered** (callable returns `internal`) |
| 35 | user offline | partial: Flutter error-state tests; no offline Firestore test |
| 36 | sign-in on another device | `account_cleanup_and_switch_test.dart` (account switch); multi-device sync via status listener not explicit |
| 37 | reinstall | server-side state only (pin, cache); **no dedicated test** |
| 38 | prayer history references stale property | `prayer_history_test.dart` (history kept independent of cache); not combined with expiry |
| 39 | different scans cover the same property | `blueprint.test.js` overlap; `pilot.test.js` I |
| 40 | new scan near a completed scan | `pilot.test.js` scenarios B–F (fill/prove planning) |

## 6. Load and concurrency

- 100 simultaneous users on one uncached area → exactly 1 Reverse GeoCoder
  call, no address looked up twice (`owners.test.js`).
- 8 simultaneous first requests pin one home (`blueprint.test.js`).
- 10 / 1,000-user simulations: **not run**. 1,000 concurrent callers on the
  local emulator is feasible but not done; transaction contention behaviour
  above 100 is unmeasured.
- Benchmarks: `docs/performance/` (cell, geo, scalability reports).

## 7. Gaps (honest)

(Closed 2026-11-24: App Check gate, Firestore outage and cache expiry
mid-request — `functions/test/resilience.test.js`; old-app compatibility —
`tool/firestore_rules_test/rules.test.js`.) Still open: offline Flutter
flows, account
deletion racing a discovery, and the integration test on a real device were
not exercised in this pass.
