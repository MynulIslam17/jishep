# Cache design — shared Melissa property cache (cache first)

Part of the [master blueprint](GPS_PARA_EL_CIELO_MASTER_BLUEPRINT.md).
Algorithms: [GEOSPATIAL_ALGORITHMS.md](GEOSPATIAL_ALGORITHMS.md). Budgets:
[MELISSA_COST_CONTROL.md](MELISSA_COST_CONTROL.md). Supersedes
`MELISSA_CACHE_STRATEGY.md` (2026-11-22).

**Status (2026-11-24)**

| Item | State |
|---|---|
| Shared canonical cache (`owner_scans`, `owner_properties/mel:{MAK}`) | Implemented; **deployed** to gps-para-el-cielo 2026-11-23 (53 pilot docs imported); cache-only in prod |
| Server-side home location, verified gate, kill switch | Implemented, tested locally (`functions/test/blueprint.test.js`); **not deployed** |
| 365-day freshness (`MELISSA_CACHE_DAYS=365`) | Code default + both `.env` files; **not deployed** (prod still runs 30) |
| 365-day TTL migration | Tool built and run on the **local emulator only**; production prepared (`tool/deploy_blueprint.sh`), not run |
| Paid discovery in production | **OFF** (`MELISSA_OWNER_DISCOVERY_ENABLED=false`, `MELISSA_GLOBAL_DAILY_CREDITS=0`) |

## 1. Two layers: shared property facts, private prayer data

```
shared (server-only, Admin SDK)              private (users/{uid}/…, owner only)
──────────────────────────────               ──────────────────────────────────
owner_scans/{scanId}        addresses        household_status/{householdId}
owner_properties/mel:{MAK}  owner facts      prayer_log/{roundId}_{householdId}
discovery_jobs/{jobId}      locks            prayer_rounds/{roundId}
melissa_usage/…             counters         notifications, devices, enrichment
primary_locations/{uid}     pinned home      (users/{uid} profile: address, lat/lon)
location_corrections/{id}   audit
```

A property cache refresh never writes under `users/{uid}`; household ids are
`mel:{MAK}` (Melissa-first) or the Overture id, so prayer status keyed by
household id survives any refresh. Account deletion
(`functions/src/cleanup.js`) removes `users/{uid}` recursively,
`primary_locations/{uid}`, per-day counters `melissa_usage/{day}/users/{uid}`
and per-user locks `discovery_jobs/u_{uid}_*`; shared documents stay.

Clients can neither read nor write any shared collection
(`firestore.rules`; rules tests "Melissa owner data…" and "server-only
location records"). Owner data reaches the app only through the
`discoverOwners` callable.

## 2. Collections and fields

### `owner_scans/{lat4}_{lon4}_r100_noapt`
One Melissa Reverse GeoCoder answer. Id from the center rounded to 4
decimals (≈11 m) + options (`scanIdFor`), so repeating the same scan writes
the same document.

| Field | Meaning |
|---|---|
| `version` | 1 |
| `source` | `melissa_reverse_geocoder` |
| `options` | `r100_noapt` (100 records, apartments excluded) |
| `center {latitude, longitude}`, `geohash5` | where it was asked; indexed for lookup |
| `requestedMeters` | asked radius (1 mile) |
| `coveredMeters` | disc proven complete: whole radius if fewer than 100 answers, else distance of the farthest answer − 1 m |
| `capped`, `recordCount` | hit the 100-record cap; number of addresses |
| `candidates[]` | `{id, mak, line, city, state, zip, latitude, longitude, units, suite}` — **no owner data** |
| `scannedAt`, `expiresAt` | freshness (`scanCacheDays`, default = `cacheDays`) |
| `ttlPolicy` | only after the TTL migration: `{days, migrationId, previousExpiresAt, migratedAt}` |

### `owner_properties/mel:{MAK}`
One Property LookupProperty answer per Melissa Address Key — including
negative answers.

| Field | Meaning |
|---|---|
| `id`, `mak` | `mel:{MAK}`, MAK |
| `status` | `named` · `not_found` · `mismatch` · `non_residential` · `multi_family` · `unclassified` · `no_owner` |
| `line, city, state, zip, latitude, longitude, geohash` (precision 9) | address and point |
| `parcelId` | dedupe of two addresses on one parcel |
| `owner {name, secondName, isCompany, isTrust}` | **only when `named`**, else `null` |
| `classification {kind, label, code, group}`, `yearBuilt` | property use |
| `source` | `melissa_property` |
| `checkedAt`, `expiresAt` | freshness: named → `cacheDays` (365); others → `negativeCacheDays` (365 since 2026-11-24; was 90) |
| `ttlPolicy`, `migration` | migration metadata, when applicable |

Not present (blueprint §4.2 asked for them): separate `lastVerifiedAt`,
`refreshEligibleAt`, owner-occupancy metadata. `checkedAt` is the
verification time and `expiresAt` the refresh-eligibility time.

### Other server collections

| Path | Purpose |
|---|---|
| `discovery_jobs/{scope}_{geohash6}` | lease for one paid discovery per ~1.2 × 0.6 km cell: `status`, `leaseOwner`, `leaseExpiresAt`, `attempts`, `creditsReserved/Used`, `requests`, `failedLookups`, `completeness`, `error` |
| `melissa_usage/{YYYY-MM-DD}` | day counters (credits per endpoint, cache hits/misses, reuse, denials) |
| `melissa_usage/{day}/users/{uid}` | per-user daily counts (`ownerDiscoveries`, `lookups`, `gapFills`) |
| `melissa_usage/month-YYYY-MM` | `ownerCredits` for the monthly budget |
| `melissa_usage/state` | `outOfCreditsAt` (6 h pause), `paidDisabled` (kill switch) + reason/by/at |
| `primary_locations/{uid}` | the home the server searches around (pinned on first use; moved only by `functions/src/location.js`) |
| `location_corrections/{id}` | immutable audit of support corrections (index `uid ASC, at ASC`) |

Per-user scope (`users/{uid}/owner_scans`, `…/owner_properties`) is the same
code with `MELISSA_OWNER_SHARED_CACHE=false`; production uses the shared
scope since 2026-11-23. `users/{uid}/owner_areas` (pre-2026-11-22 per-area
results) is still served when valid (`legacy`).

Not part of this cache: `enrichHousehold` stores per-user results in
`users/{uid}/enrichment/{householdId}` and the gap-filler in
`users/{uid}/gap_areas/{lat3_lon3}`. Both are per user (not shared) and off
in production; they also take `MELISSA_CACHE_DAYS`.

## 3. Request flow (cache first)

`discoverOwners` (`functions/src/owners.js`), in order:

1. `allowOwnerNames` must be on, caller signed in, `cacheDays > 0`.
2. **Home**: `primaryLocation(db, uid)` — `primary_locations/{uid}`, else
   copy `users/{uid}.latitude/longitude` there (create-only). Client
   coordinates, if sent, must be within `locationToleranceMeters` (250 m)
   of it, else `permission-denied / location_not_authorized`.
3. `serveFromCache` at the home (see GEOSPATIAL_ALGORITHMS §3).
4. `complete` or `empty` → return (0 credits, `ownerCacheHits`).
5. `unknown` → try the legacy per-area result.
6. `planMissing` → what a paid discovery would buy. If discovery is off or
   nothing useful can be bought → return stored records + `missing`.
7. Paid wanted: refuse before any lease if the account is unverified
   (`limited: unverified`) or the kill switch is on (`limited: paid_disabled`).
8. Lease `discovery_jobs/{scope}_{geohash6}`; on success re-read the cache
   (double-checked) and re-plan. Not acquired → wait ≤ 20 s, then return
   what is stored (`pending` if still running).
9. Reserve estimated credits atomically (budgets); over a limit → stored
   records + `limited: <reason>` (no throw, no call).
10. Reverse GeoCoder scan if needed → write the scan; Property lookups
    nearest first, 4 at a time, each answer written as it arrives.
11. Settle (give back unused credits), finish the lease, count, return.

Never: a Melissa call while the user types or drags the pin (setup uses
`nearestArea(preview: true)`, Overture only), when marking a prayer,
starting a round, switching tabs or refreshing; never for any place other
than the saved home (the app has no way to view another place since
2026-11-24, and the server refuses other coordinates anyway).

## 4. Freshness (365 days) is not deletion

| Record | Fresh for | After expiry |
|---|---|---|
| `owner_properties` named | `MELISSA_CACHE_DAYS` = 365 | not served as fresh; **document kept**; re-bought only by an authorized paid discovery within budget |
| `owner_properties` negative | `MELISSA_OWNER_NEGATIVE_CACHE_DAYS` = 365 (was 90) | the address counts as unresolved again (a paid discovery may look it up) |
| `owner_scans` | `scanCacheDays` = `cacheDays` (365) | the scan no longer proves coverage → `expired`/`partial` |
| `users/{uid}/enrichment`, `gap_areas` | `MELISSA_CACHE_DAYS` | same rule |

No code path deletes cache documents because of `expiresAt` (no TTL policy
is configured on these collections, no cleanup job). Data retention is a
separate decision (none implemented). A failed refresh never removes an
existing record: errors and timeouts are not written.

Fixed 2026-11-24: negatives used to expire at 90 days inside 365-day scans,
so a still-fresh scan's not-found / commercial addresses would have become
unresolved and been bought again (9 credits each) once paid discovery was
on. Negatives now last as long as scans (365 d) — test "negative answers
last as long as the scan" in `functions/test/blueprint.test.js`.

### 365-day migration (`functions/tool/migrate_cache_ttl.js`)

Extends every root `owner_properties` answer (named and negative) and root
`owner_scans` to `checkedAt|scannedAt + 365 d`. Never shortens, never
deletes, only `expiresAt` + `ttlPolicy` change, update-time precondition
(nanosecond exact), idempotent; `rollback` restores the backed-up value.

```
plan     → counts (read-only)
backup   → ttl-backup-<id>.json (path, old expiresAt, updateTime), mode 600
apply    → update with lastUpdateTime precondition; skip if already ≥ target
verify   → every eligible doc at target (exit 2 if not)
rollback → restore old expiresAt on docs still carrying this migrationId
```

Local run, emulator project `gps-para-el-cielo`, 2026-11-24 (emulator export
backup `.local-backups/pre-ttl365-20261124-112853` taken first): 53 documents
(52 properties + 1 scan). First pass (named + scans): **51 extended**,
verify `ok: true`, re-apply `updated: 0, skippedAlreadyOk: 51`. After the
negative-window fix, second pass: the **2 negative records extended**, verify
`ok: true` with **all 53** at 365 days. Tests: `functions/test/ops_tools.test.js`.
Production: not run (step 5 of `tool/deploy_blueprint.sh`).

## 5. Consistency, concurrency, recovery

| Concern | Mechanism |
|---|---|
| Same area requested by many users at once | one lease per `{scope}_{geohash6}`; others wait/poll and read the result (test: 100 users → 1 Reverse call) |
| Lease holder crashes | lease expires (`leaseMs` 150 s); next request resumes, buying only what is still unresolved (stored answers are reused) |
| Retry of the same request | deterministic ids (scan, property, job); finished lookups are never repeated (test "retry after partial progress…") |
| Two first requests pin a home | `create()` on `primary_locations/{uid}`; loser re-reads (test) |
| Profile deleted and re-created elsewhere | server keeps the pinned home; client coordinates refused |
| Melissa error | not stored; `UNCHARGED` errors not counted as spend; `out_of_credits`/licence errors stop the job |
| Kill switch | `melissa_usage/state.paidDisabled` read inside every reservation transaction |

## 6. History (from the superseded docs)

- 2026-11-22 Rancho del Rey pilot (Chula Vista, 32.6435, −117.0185): Reverse
  GeoCoder 100 addresses (200 credits) + 52 Property lookups (468) = **668
  credits for 50 named single-family homes**, 2 not found; disc proven
  complete ≈ 300 m. Rebuilt from recordings with 0 network
  (`functions/test/pilot.test.js`).
- Before 2026-11-22: per-user, per-~110 m area cache (`owner_areas`), 30 days.
- 2026-11-23: shared scope switched on in production; 52 + 1 pilot docs
  imported (create-only, verified identical), expiring 2026-12-22 under the
  old 30-day rule until the TTL migration runs.
- Document sizes: a scan ≈ 20 KB, a property ≈ 0.6 KB; one single-field
  `in` query on `geohash5`, no composite index for the cache.
