# Geospatial algorithms

Part of the [master blueprint](GPS_PARA_EL_CIELO_MASTER_BLUEPRINT.md). Data
model: [CACHE_DESIGN.md](CACHE_DESIGN.md). Code:
`functions/src/property_cache.js`, `functions/src/owners.js`,
`lib/core/data/cell_source.dart`, `lib/core/data/owner_discovery.dart`.

The app has two spatial sources:

1. **Overture homes** (free) — `cells/{geohash prefix}` documents read by the
   app (`CellArea`), the base list of homes everywhere data is loaded.
2. **Melissa owner records** (paid, cached) — `owner_scans` +
   `owner_properties`, read only by `discoverOwners` on the server.

`OwnerOverlayArea` (app) puts a recorded owner name on an Overture home only
when a stored owner record has the **same street address** (abbreviations
normalized) within 250 m. Owner records never add or replace homes.

## 1. Primitives

| Function | What | Notes |
|---|---|---|
| `haversineMeters(lat1, lon1, lat2, lon2)` | great-circle distance, R = 6,371,008.8 m | used for every distance and sort |
| `offset(lat, lon, m, bearing)` | point at distance/bearing | flat approximation, short distances only |
| `geohash(lat, lon, p)` | base-32 geohash | matches the reference encoder (test) |
| `cellsAround(lat, lon, meters, p=5)` | every precision-5 cell touching the box ±meters | sampled every 0.02° (< half a cell), so boundary cells are included |
| `coveredRadius(lat, lon, discs, max, step=10)` | largest disc around the point inside the union of scan discs | exact for one disc; else ring sampling, reported one step short (errs toward "not covered") |

## 2. Why geohash, not H3

Evaluated and **rejected**: H3 would add a native/JS dependency and a second
index scheme, while geohash already gives what the cache needs — a single
indexed equality (`geohash5 in [...]`) per ≤30 cells, correct boundary
handling via `cellsAround`, and the same scheme the Overture cells use.
Exact-coordinate matching is never the cache key: any scan whose disc can
reach the search disc is considered.

## 3. Nearest K with coverage — `serveFromCache`

```
serveFromCache(scope, point, target=50, now, cfg):
  searchMeters = maxMiles (1) × 1609.344
  cells  = cellsAround(point, maxScanMeters + searchMeters)        # ≈ 2 mi box
  scans  = ⋃ query(owner_scans where geohash5 in cells[i..i+30])
  keep scan s if dist(point, s.center) − s.coveredMeters ≤ searchMeters
           and s.expiresAt > now                (else count expired)
  byId   = HashMap; for c in s.candidates: if id seen → duplicateAddresses++
                                           else byId[id] = c + distance
  all    = sort(byId.values, by distance)                           # haversine
  R      = coveredRadius(point, scan discs, searchMeters, 10 m)
  walk all nearest first in chunks of 60 (getAll owner_properties):
      skip suites / multi-unit (units > 0) unless includeMultiFamily
      missing or expired property → unresolved (remember first distance)
      not named / no owner → excluded
      parcelId already used → duplicateParcel  (one home per parcel)
      else append to named until target
  completeness =
      no live scans          → expired (if some expired) else unknown
      |named| ≥ target ∧ last ≤ R ∧ firstUnresolved ≥ last → complete
      R ≥ searchMeters ∧ no unresolved within R → complete (fewer exist) | empty
      otherwise → partial
```

It returns `records`, `completeness`, `coveredMeters`, the unresolved
addresses within R, stats (scans, candidates, duplicates, reads…), and the
scan address density (used to estimate unseen addresses).

**Finding 50 is not proof.** `complete` requires that the 50th named home
lies inside the proven disc and nothing closer is unresolved; 50 stored
names from a scan centred elsewhere are returned as `partial`.

### Completeness states vs the blueprint (§5.4)

| Blueprint state | Implemented as | Honest note |
|---|---|---|
| `complete` | `complete` | same meaning; also "whole radius resolved, fewer exist" |
| `partial` | `partial` | same |
| `unavailable` | `unknown` (nothing stored) or `empty` (whole radius resolved, no named home) | two distinct codes, no literal `unavailable` |
| `expired` | `expired` | only expired scans near the point |
| `refresh_pending` | **does not exist** | nearest equivalent: `pending: true` (another request holds the lease) |
| `error` | **does not exist as a state** | errors are thrown as callable errors (`unavailable`, `resource-exhausted`, …) |
| — | `legacy` | pre-2026-11-22 per-area result |
| — | `limited: <reason>` | stored records served, paid part refused (budget, kill switch, unverified) |

## 4. What is missing — `planMissing`

```
if complete or empty: nothing
scanHere = some live scan centred ≤ 25 m from the point
fill (default):  short = target − |named|
    want = ceil(short / namedRate (0.9))
    knownEnough = |unresolved| × namedRate ≥ short
    scanNeeded  = ¬knownEnough ∧ ¬scanHere   # same point again returns the same 100
    lookups = scanNeeded ? min(maxLookups, max(fromKnown, want)) : min(|unresolved|, want, maxLookups)
prove (completeCoverage=true only): also look up unresolved addresses closer
    than the 50th home, and scan here if the proven disc does not reach it;
    unseen ≈ density × π × (last² − R²)
credits = (scanNeeded ? 100 × 2 : 0) + lookups × 9
```

The response always includes `missing = {scanNeeded, lookupsNeeded,
estimatedCredits, exhaustedAtPoint, toProve}`, so cache-only mode reports
exactly what a paid discovery would buy.

## 5. Overlap examples (all tested in `functions/test/blueprint.test.js`)

| Case | Result |
|---|---|
| A and B 1 m apart | B served entirely from A's purchase, 0 credits |
| B between cached A and C (C repeats 20 of A's MAKs) | both scans merged, 20 duplicates counted once, sorted, 50 homes, 0 calls |
| B overlaps five scans | one answer, every property once |
| B across a geohash-5 edge from A | A's scan still found (`cellsAround`) |
| suites / multi-unit buildings | skipped; second owner kept; no-owner excluded |
| only 15 valid homes | 15 returned, `coverage: partial`, never padded |
| pilot scenarios 0 / 50 / 200 / 400 m / 2 / 5 km | `functions/test/pilot.test.js` (reuse up to the proven disc, honest `partial`, cache miss far away) |

## 6. Complexity

Let S = live scans near the point, C ≤ 100 candidates per scan,
N = S·C merged candidates (after dedupe), K = target (50), P = property reads.

| Step | Time | Firestore |
|---|---|---|
| cell list | O(cells) ≈ 10–20 | ⌈cells/30⌉ queries |
| merge + dedupe (hash map) | O(S·C) | — |
| sort by distance | O(N log N) | — |
| coveredRadius | O(D) for one disc; O((R/step)·(2πR/step)·D) sampled, D = discs | — |
| walk | O(P) | P reads in chunks of 60 (≈ K/namedRate + exclusions) |

Pilot cache hit: 1 scan query + 60 property reads = 61 reads; overlap
(partial) ≈ 101.

**Bounded heap?** A top-K heap would make the selection O(N log K) instead
of O(N log N). Not needed: N ≤ 100 · S (a few hundred in practice), the sort
is microseconds, and the walk must visit candidates in order anyway (it
skips unresolved/excluded ones until K are named, so K is not known up
front). The cost is dominated by Firestore reads, not CPU. Sort kept.

Memory: bounded by the scans touching a ≈ 2-mile box; no geographic dataset
is loaded into memory.

## 7. Overture side (app, unchanged by this blueprint)

`CellArea` (`lib/core/data/cell_source.dart`): geohash-5 cells
(`cellPrecision = 5`; dense cells split to 6/7), reads the 3×3 block, then
the 5×5 ring only if fewer than 50 homes, children nearest-first only while
closer than the current 50th home; dedupe by id; haversine sort;
`maxHouseholds = 50`. Measured in `docs/performance/cell_benchmark.md`
(median 13 cold reads, 174 KB, p99 25 reads) — see also
[NATIONWIDE_CELLS.md](NATIONWIDE_CELLS.md).
