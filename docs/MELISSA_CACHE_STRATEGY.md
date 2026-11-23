# Melissa cache strategy (cache first, pay only for what is missing)

Status 2026-11-22: **implemented and tested locally; nothing deployed;
production Melissa access and owner-name sharing stay OFF.**
Code: `functions/src/property_cache.js`, `functions/src/owners.js`,
`functions/src/guard.js`. Tests: `functions/test/owners.test.js`,
`functions/test/pilot.test.js`, `functions/test/cache_geo.test.js`.

## 1. Spending lock-down (fail closed)

| Where | What can reach Melissa | Proof |
|---|---|---|
| Tests | nothing: `test/no_network.js` makes every non-local fetch throw (loaded by every `npm test*` script) | `cache_geo.test.js` "tests themselves cannot reach the internet"; every run records 0 blocked attempts |
| Functions emulator | only **saved** answers (`functions/.melissa-recordings`); an unrecorded request is refused with no network access. Only `MELISSA_EMULATOR_LIVE=true` (never set) would allow a live call. `MELISSA_REPLAY_ONLY` no longer matters. The global `fetch` is wrapped too, so code that forgets the guard (as `discoverNearby` did) is still blocked | `guard.js` `melissaFetchFor`, `installGlobalGuard`; test "guard: in the emulator an unrecorded Melissa request never reaches the network" |
| Local discovery switch | `MELISSA_OWNER_DISCOVERY_ENABLED=false` in `functions/.env.local`: cache-only, reports what is missing | emulator call for an unseen area → `unknown`, 0 credits |
| Production | all Melissa switches OFF in `functions/.env.gps-para-el-cielo`; functions not deployed | file content |

## 2. What is stored (each fact once)

| Collection | One document per | Contents | TTL |
|---|---|---|---|
| `owner_scans/{lat4_lon4_r100_noapt}` | Reverse GeoCoder answer | center, `coveredMeters` (disc proven complete), up to 100 addresses (id, MAK, line, city, state, zip, lat, lon, units, suite) — **no owner data** | `scanCacheDays` 30 |
| `owner_properties/mel:{MAK}` | address (Melissa Address Key) | `status` = `named` / `not_found` / `mismatch` / `non_residential` / `multi_family` / `unclassified` / `no_owner`; owner (`name`, `secondName`, `isCompany`, `isTrust`) **only when named**; property use; parcel id | named: `MELISSA_CACHE_DAYS` 30 (licence); exclusions: `MELISSA_OWNER_NEGATIVE_CACHE_DAYS` 90 |
| `discovery_jobs/{scope}_{geohash6}` | area being bought | lease owner / expiry, idempotency key, credits reserved / used, requests, failures, status | overwritten per job |
| `melissa_usage/{day}`, `melissa_usage/month-YYYY-MM` | day / month | ESTIMATED credits, discoveries, cache hits / misses, Melissa requests, failed lookups | kept |

Scope: shared (root collections) only when `MELISSA_OWNER_SHARED_CACHE=true`
(needs Melissa's written OK); otherwise the same documents under
`users/{uid}/owner_scans` and `users/{uid}/owner_properties` — reuse across
one user's own searches and restarts, never across users. Clients can never
read or write any of these (`firestore.rules`, 3 rules tests). Household ids
stay `mel:{MAK}` (unchanged), so prayer statuses keep matching.

Size: a scan document ≈ 20 KB (100 addresses), a property document ≈ 0.6 KB.
Nothing approaches Firestore's 1 MiB document limit; no composite index is
needed (one single-field `in` query on `geohash5`).

## 3. Nearest 50 with honest completeness

`serveFromCache` (property_cache.js):

1. Load valid scans whose disc can touch the search disc: query
   `geohash5 in cellsAround(point, 1 mile + 1 mile)` — every precision-5 cell
   touching that box, so a scan just across a cell edge is found (test G).
2. Merge their addresses in a hash map by id (duplicates counted once),
   compute haversine distance to the point, sort.
3. `R` = radius around the point covered by the union of scan discs
   (exact for one disc; for several, sampled on rings every 10 m and
   reported one step short).
4. Walk addresses nearest first, reading property answers in chunks of 60
   (`getAll`), until 50 named homes (one per parcel).
5. Completeness:

| Status | Meaning |
|---|---|
| `complete` | the 50th named home lies within `R` and every closer address is resolved — provably the nearest 50 in Melissa's deliverable addresses; or the whole 1-mile radius is resolved and fewer exist |
| `partial` | stored homes returned, but closer ones may exist (point outside / near the edge of the scanned disc, or unresolved addresses) |
| `empty` | the whole radius is resolved and has no named residential home |
| `expired` | only expired scans here: nothing served, nothing refreshed automatically |
| `unknown` | nothing stored here |
| `legacy` | an older per-area result (`users/{uid}/owner_areas`, still valid) |

The response also says what is missing:
`missing = {scanNeeded, lookupsNeeded, estimatedCredits, toProve: {...}}`.
`fill` = what it costs to reach 50 named homes; `toProve` = what it would
cost to make the result provably the nearest 50 (a scan at the point plus
lookups of closer unknown addresses; upper estimate from the stored address
density, capped at 80 lookups). Paid discovery buys only `fill` unless
`completeCoverage` is on.

## 4. Paid discovery (future, authorized production only)

Priority order: in-memory (app session) → stored scans + property answers
(shared if licensed) → negative cache → incremental discovery → paid calls.

- **One job per area**: lease in `discovery_jobs/{scope}_{geohash6}`
  (~1.2 × 0.6 km). A cheap read first (no transaction contention), then a
  transaction; after taking the lease the cache is **read again** (another
  request may have just finished: double-checked locking). Others wait up to
  20 s (polling) and read the result; if still running they get
  `pending: true` with what is stored, and the app retries twice after 3 s.
  Test: 100 simultaneous users → 1 Reverse GeoCoder call, no address looked
  up twice, 1 paid result, 99 free.
- **Budgets** (estimated credits, reserved atomically before any call,
  unused given back): ≤ 920 per request (lookups shrink to fit), 5 paid
  discoveries per user per day, 2,000 per day and 20,000 per month app-wide,
  6 h pause after Melissa GE14 (out of credits). Over a limit with stored
  homes → those homes are returned (`limited`), no call.
- **Resumable**: the scan and every property answer are written as they
  arrive; a crashed job's lease expires and the next request buys only what
  is still missing (test "a crash part-way").
- **Negative cache**: not found / mismatch / commercial / multi-family / no
  owner are stored without owner data and not looked up again for 90 days.
  Network errors and timeouts are NOT stored (retried later).
- **Retries**: Property 1 retry (429 / 5xx / network); Reverse GeoCoder 0.
- **Idempotency**: deterministic ids — scan id from the rounded center,
  property id from the MAK, job id from the area cell.

Remaining risk (cannot be removed by our code): Melissa may bill a request
whose answer never arrived (timeout after Melissa processed it). Those are
counted as not charged in our estimate. `melissa_usage` is an estimate;
Melissa's own usage report is the billing authority. Compare them monthly.

## 5. What the app does

- `OwnerArea` (lib/core/data/owner_discovery.dart): one call per area per
  session (in-memory), `pending` → retry, `unknown`/`expired` with nothing
  stored → Overture addresses with the reason, `partial` → stored homes with
  "Nearest stored homes · …" or "N homes found so far · …".
- Location setup preview and pin dragging use Overture only
  (`nearestArea(preview: true)`): never Melissa (test "trying spots never
  asks for property owners").
- Starting a new prayer round never calls Melissa (same homes).

## 6. Licence gates (Melissa written confirmation needed)

| Switch | Needs |
|---|---|
| `MELISSA_ALLOW_OWNER_NAMES=true` | display of recorded owner names to app users |
| `MELISSA_CACHE_DAYS` | how long owner records may be stored |
| `MELISSA_OWNER_SHARED_CACHE=true` | one stored record shown to several users |
| `MELISSA_OWNER_NEGATIVE_CACHE_DAYS` | storing "no match" facts (no owner data) |
| `MELISSA_OWNER_DISCOVERY_ENABLED=true` | spending approval |

Until then real owner names exist only on the developer's machine
(emulator + recordings + backups, all git-ignored).
