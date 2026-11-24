# GPS PARA EL CIELO — architecture

Status **2026-11-24**. Part of the
[master blueprint](GPS_PARA_EL_CIELO_MASTER_BLUEPRINT.md); diagrams in
[diagrams/](diagrams/README.md). Production (`gps-para-el-cielo`) runs the
2026-11-23 backend; everything marked **(2026-11-24, local)** is implemented
and tested on emulators but **not deployed** (owner's choice: local only).

## 1. Overview

```
 Flutter app (iOS / Android)                         Firebase project gps-para-el-cielo
 ───────────────────────────                         ─────────────────────────────────────────────
 Location setup (once, at signup)                    Firestore rules
   address / GPS → pin → preview (Overture only)       users/{uid}: location fields locked once set
   → users/{uid}.latitude/longitude/address              (2026-11-24, local)
 Home / Neighborhood / Prayer List / Follow-up        Cloud Function discoverOwners (callable)
   HouseholdStore (one neighborhood per session)        0 auth → saved home only: primary_locations/{uid}
     │                                                    (pinned on first use; client point must be
     ├─ Overture cells/{geohash}  (free, base list)        ≤ 250 m away)            (2026-11-24, local)
     │                                                  1 serveFromCache ─ owner_scans + owner_properties
     └─ OwnerOverlayArea → OwnerArea ── callable ──►    2 complete/empty → return, 0 credits
          (owner names matched by street address)       3 paid wanted? enabled · verified · kill switch off
                                                          · lease discovery_jobs · reserve melissa_usage
 users/{uid}/… (private; rules)                           (2026-11-24 gates local; enabled=false in prod)
   household_status, prayer_log, prayer_rounds,        4 Reverse GeoCoder + Property (guard.js) → store
   notifications, devices                                 each answer, settle credits, release lease
                                                      enrichHousehold, discoverNearby (budget 0 in prod)
 Operator tools (functions/tool, Admin SDK, ADC)      cleanupDeletedUser (auth trigger)
   melissa_ops (kill switch, usage report)            Secret Manager: MELISSA_CREDIT_LICENSE
   migrate_cache_ttl (365-day policy)
   location_admin (status, audited correction)
```

The neighborhood is **Overture-first**: the list of homes always comes from
the free Overture address cells; Melissa owner records are an overlay that
adds a recorded owner to homes at the same street address
(`OwnerOverlayArea`, `lib/core/data/owner_discovery.dart`). Clients never
read Melissa data from Firestore; it reaches the app only through
`discoverOwners`.

## 2. Firestore data model

| Path | Written by | Read by | Purpose |
|---|---|---|---|
| `users/{uid}` | owner (rules) | owner | profile, **primary location** (`address`, `latitude`, `longitude`, `locationConfirmedAt`, `locationVersion`), `dailyPrayerTarget`, `radiusHomes`, `prayerCycleStartedAt` |
| `users/{uid}/household_status/{householdId}` | owner | owner | prayed, visited, invited, follow-up, notes, private resident name |
| `users/{uid}/prayer_log/{roundId}_{householdId}` | owner | owner | append-only prayer history |
| `users/{uid}/prayer_rounds/{roundId}` | owner | owner | fixed round membership, start / completion |
| `primary_locations/{uid}` **(2026-11-24, local)** | function / operator | function | the home the server searches around; pinned on first use; moved only by an audited correction |
| `location_corrections/{id}` **(2026-11-24, local)** | operator tool | operator tool | immutable audit: who, when, from, to, reason |
| `owner_scans/{scanId}` | function | function | Reverse GeoCoder answer + proven coverage disc (`coveredMeters`) |
| `owner_properties/mel:{MAK}` | function | function | one Property answer per address (named or excluded) |
| `discovery_jobs/{scope}_{geohash6}` | function | function | lease / idempotency / credits reserved & used |
| `melissa_usage/{day}`, `month-YYYY-MM`, `state`, `{day}/users/{uid}` | function / operator | function / operator | estimated credits, counters, per-user limits, `paidDisabled` kill switch, out-of-credits pause |
| `cells/{geohash}` | admin seed | signed-in users | Overture addresses (base list, setup preview) |
| `households/{id}` | admin | signed-in users | legacy shared directory (demo data) |
| `support_messages/{id}` | user | user (own) | Contact support (also used for location corrections) |

Shared property data and private prayer activity never mix: owner records
are stored once (`mel:{MAK}`), never copied into user documents; household
ids are stable (`mel:{MAK}` / Overture ids), so a cache refresh cannot create
duplicate prayer records. Details: [CACHE_DESIGN.md](CACHE_DESIGN.md).

## 3. Location model (blueprint §2.1)

1. Chosen once in Location setup (`LocationSetupController.confirmLocation`
   → `AuthService.updateLocation`), with `locationConfirmedAt` (server
   time) and `locationVersion: 1`; falls back to the plain fields if old
   rules are live.
2. Locked: the rules refuse any client change of the location fields once
   latitude/longitude exist (`locationChangeAllowed`). Existing users with
   coordinates are locked automatically (no migration).
3. Server-authoritative: `discoverOwners` ignores client coordinates except
   to reject them (> 250 m from the pinned home → `location_not_authorized`).
4. Corrections: support only, `functions/tool/location_admin.js correct`
   (operator + reason, ≤ 2 per user per 365 days, audited).
5. The app has no location editor and no way to view another place
   (Profile shows the home read-only; "Look around another place" was
   removed 2026-11-24 because the client approved signup-only location).
   Every screen shows the saved home's neighborhood.

## 4. Geospatial algorithm

Geohash-5 cell covering (boundary-safe), hash-map dedupe by id, parcel
dedupe, haversine distances, nearest-first walk with chunked `getAll`
reads, coverage radius of the union of scan discs, completeness states.
See [GEOSPATIAL_ALGORITHMS.md](GEOSPATIAL_ALGORITHMS.md).

## 5. Concurrency and credit protection

One paid job per area (lease + double-checked read), atomic reservation
against per-request / per-user / daily / monthly / app-wide budgets, unused
credits returned, partial work stored as it arrives, out-of-credits pause,
**kill switch, verified-account gate, server-side location gate
(2026-11-24, local)**. Budget-limited answers return stored records with
`limited: <reason>` instead of an error (no retry storms). Tested: 100
simultaneous users → 1 paid discovery. See
[MELISSA_COST_CONTROL.md](MELISSA_COST_CONTROL.md).

## 6. Prayer rounds and history

- Fixed membership per round in `prayer_rounds/{roundId}.members`
  (id, point, street, city — never owner names). A cache change, a late
  Melissa answer or a refresh never changes them.
- Starting a round copies the current members; no lookup, no credits.
- Praying writes the status, then `prayer_log/{roundId}_{householdId}`;
  a new round never overwrites history.
- Lifetime count: max(`prayer_log` count, homes prayed).
- A support correction of the home starts the new neighborhood on the next
  app open; history, statuses and follow-ups are untouched.

## 7. Name display

1. the user's private name for the home → 2. recorded owner
("Property Owner (Public Record)", "The owner may not live here.") →
3. street address → 4. "Unknown Resident" only without an address.

## 8. Environments and switches

| | Tests | Local emulator | Production (deployed 2026-11-23) |
|---|---|---|---|
| Melissa network | blocked (`test/no_network.js`) | replay only (`guard.js`) | real, only if a paid switch is on |
| `MELISSA_GLOBAL_DAILY_CREDITS` | per test | 0 | **0** (no paid call possible) |
| `MELISSA_OWNER_DISCOVERY_ENABLED` | per test | false | **false** |
| `MELISSA_ALLOW_OWNER_NAMES` | per test | true | **true** (owner's direction 2026-11-23) |
| `MELISSA_OWNER_SHARED_CACHE` | per test | true | **true** |
| `MELISSA_CACHE_DAYS` | per test | 365 | 30 deployed → **365 in the env file, not deployed** |
| `MELISSA_OWNER_REQUIRE_VERIFIED` / `…_LOCATION_TOLERANCE_M` | per test | true / 250 | not deployed |
| `MELISSA_REQUIRE_APP_CHECK` (soft) | per test | false (emulator) | not deployed → **true** in the env file |
| `ENFORCE_APP_CHECK` (hard) | — | false | **false** (until builds without App Check are retired) |
| App `MELISSA_OWNERS` | per test | true | true in release builds |

## 9. Deployment

One command, prepared and not run: `tool/deploy_blueprint.sh
--approve=gps-para-el-cielo` (backups → dry run → rules + indexes →
functions → 365-day migration → live check). See
[PRODUCTION_DEPLOYMENT.md](PRODUCTION_DEPLOYMENT.md).
