# GPS PARA EL CIELO — architecture (Melissa-first, cache-first)

Status 2026-11-22: implemented and tested **locally**. Nothing deployed.
Production Melissa calls and owner-name display stay OFF until Melissa's
written licence and the client's approvals. See also
`docs/MELISSA_CACHE_STRATEGY.md`, `docs/COST_MODEL.md`, `docs/APP_FLOW.md`,
`docs/DEPLOY_FUNCTIONS.md`.

## 1. Overview

```
 Flutter app (iOS / Android)                     Firebase project gps-para-el-cielo
 ───────────────────────────                     ─────────────────────────────────────────
 Home / Neighborhood / Prayer List                Cloud Function discoverOwners (callable)
   │  HouseholdStore (one neighborhood,             1 serveFromCache ── owner_scans (addresses)
   │   in-memory for the session)                   │                └─ owner_properties (owners,
   │                                                │                     exclusions)  [shared or
   ├─ OwnerArea ── callable ───────────────────────►│                     users/{uid}/…]
   │   (pending → retry; nothing stored →           2 complete? → return (0 credits)
   │    Overture fallback)                          3 enabled? lease discovery_jobs/{area}
   │                                                │   reserve credits (melissa_usage)
   ├─ Overture cells (cells/{geohash})              │   Reverse GeoCoder ─┐ guard.js
   │   setup preview, fallback                      │   Property (MAK) ───┤ (emulator: replay
   │                                                │                     │  only, no network)
   └─ users/{uid}/…  (private, rules)              4 store each answer, settle credits
        household_status/{householdId}           Cloud Function cleanupDeletedUser (auth)
        prayer_log/{roundId}_{householdId}          deletes users/{uid}/** + counters + locks
        prayer_rounds/{roundId}
        notifications, devices                   Melissa key: Secret Manager only
```

Clients never read Melissa data from Firestore directly; owner records reach
the app only through the function, which checks the licence switches.

## 2. Firestore data model

| Path | Written by | Read by | Purpose |
|---|---|---|---|
| `users/{uid}` | owner | owner | profile, home point, `dailyPrayerTarget`, `prayerCycleStartedAt` |
| `users/{uid}/household_status/{householdId}` | owner | owner | prayed (latest), visited, invited, follow-up, notes, private name |
| `users/{uid}/prayer_log/{roundId}_{householdId}` | owner | owner | **append-only history**: one event per home per round |
| `users/{uid}/prayer_rounds/{roundId}` | owner | owner | round membership (`householdIds`), start / completion |
| `owner_scans/{id}` *(shared)* or `users/{uid}/owner_scans/{id}` | function | function | Reverse GeoCoder answers + proven coverage disc |
| `owner_properties/mel:{MAK}` *(shared)* or `users/{uid}/owner_properties/…` | function | function | one Property answer per address (named or excluded) |
| `discovery_jobs/{scope}_{geohash6}` | function | function | lease, idempotency, credits reserved / used |
| `melissa_usage/{day}`, `…/month-YYYY-MM`, `…/{day}/users/{uid}` | function | function | estimated credits, hits / misses, per-user limits |
| `users/{uid}/owner_areas/{key}` | (old function) | function | older per-area results; still served while valid, not written any more |
| `cells/{geohash}` | admin seed | signed-in users | Overture addresses (fallback, preview) — unchanged |

Design choices: each property stored once (owner details never copied into
user records); area documents hold addresses only (≈ 20 KB); user history
is separate from shared geographic data; household ids (`mel:{MAK}`) are
unchanged so existing statuses keep matching; `version: 1` on new documents.

## 3. Geospatial algorithm

See `MELISSA_CACHE_STRATEGY.md` §3: geohash-5 cell covering (boundary-safe),
hash-map dedupe, haversine distances, bounded nearest-K walk with chunked
reads, coverage radius of the union of scan discs, and the completeness
states `complete / partial / empty / expired / unknown / legacy`. A result
is called the nearest 50 only when coverage proves it.

## 4. Concurrency and credit protection

One paid job per area (lease + double-checked read), atomic reservation
against per-request (920), per-user (5/day), daily (2,000) and monthly
(20,000) budgets, unused credits returned, partial work stored as it
arrives, 6 h pause on out-of-credits, negative cache 90 days, bounded
retries. Tested: 100 simultaneous users → 1 paid discovery.

## 5. Prayer rounds and history

- **Fixed membership.** A round's homes are recorded once in
  `prayer_rounds/{roundId}.members` (id, point, street, city — never owner
  names; plus `center` and `target` = Settings count). `HouseholdStore`
  shows exactly these homes for the whole round, using fresher details when
  loaded. A changed cache answer, a Melissa result arriving later, or a
  search elsewhere never changes them. Only explicit user actions do:
  moving the saved home > 100 m (the round gets the new neighborhood, same
  round id) or a new Settings count (existing homes kept, nearest added or
  farthest dropped). A round is fixed only from a settled answer
  (`OwnerArea.isSettled`: not pending, not a network/server error).
- **Same homes every round.** Starting a round copies the current round's
  members (`HouseholdStore.nextRound`); no lookup, no cache read.
- Day plan unchanged: today's goal (3/5/10/15) nearest-first among homes not
  prayed this round; "today" by the phone's local date. Home and the Prayer
  List rebuild together at midnight and when the app is reopened on a later
  day (`DayChangeWatcher`).
- Praying writes the status, then `prayer_log/{roundId}_{householdId}`
  (idempotent id; a new round never overwrites history). The history write
  never fails the prayer (old rules deny it). Un-praying deletes only this
  round's event.
- Starting a round (`UserRepository.startPrayerRound`): round documents
  (close previous, record new members) best-effort, then
  `prayerCycleStartedAt`. Visits, invitations, follow-ups untouched.
- Lifetime count: Profile "My impact" → **Prayers** =
  max(`prayer_log` count, homes prayed), kept current locally. The max
  covers prayers saved before the history existed.
- Rules compatibility: `functions/tool/check_rules_compat.js` (read-only;
  emulator by default) lists existing documents the new rules would block.

## 6. Name display

1. the user's own name for the home (private) → 2. recorded owner, labelled
"Property Owner (Public Record)", "The owner may not live here.", company /
trust tag, second owner in the details → 3. street address → 4. "Neighbor"
only with no address. Owner names appear only when the server allows them.

## 7. Environments and switches

| | Tests | Local emulator | Production |
|---|---|---|---|
| Melissa network | blocked (`test/no_network.js`) | replay only (`guard.js`) | real, only if switched on |
| `MELISSA_ALLOW_OWNER_NAMES` | per test | true (`.env.local`) | **false** |
| `MELISSA_OWNER_DISCOVERY_ENABLED` | per test | **false** (cache-only) | **false** |
| `MELISSA_OWNER_SHARED_CACHE` | per test | false | **false** |
| App `MELISSA_OWNERS` | per test | `--dart-define=MELISSA_OWNERS=true` | not set |
| Data | demo project ids | `.emulator-data/` (git-ignored) via `tool/emulators.sh` | none seeded |

## 8. Production deployment and migration plan (needs approval)

1. Melissa written licence (display, storage period, sharing, negative
   cache, non-FCRA use).
2. Client: enable APIs, grant roles (`DEPLOY_FUNCTIONS.md` §1).
3. Deploy rules (adds `prayer_log`, `prayer_rounds`, server-only Melissa
   collections) — test first with `tool/firestore_rules_test`.
4. Deploy functions with discovery OFF (cache-only; nothing stored yet in
   production, so every area is `unknown` → Overture fallback).
5. App release with `MELISSA_OWNERS=true` only after 1.
6. Turn on `MELISSA_OWNER_DISCOVERY_ENABLED` with budgets agreed by the
   client; turn on `MELISSA_OWNER_SHARED_CACHE` only if licensed.
7. Migration: none destructive. New collections are additive; old
   `owner_areas` documents are still served until they expire. Household
   ids are unchanged. The local pilot data is **not** uploaded to
   production.
