# Melissa credit and Firestore cost model

All figures are **estimates** from the code's rules and one real pilot. They
are not guaranteed savings. Melissa's own usage report is the billing
authority; the dollar price per Melissa credit is not on record.

## 1. Measured basis (Rancho del Rey pilot, 2026-11-22)

| | Value |
|---|---|
| Reverse GeoCoder | 100 addresses × 2 = 200 credits |
| Property lookups | 52 × 9 = 468 credits (2 not found) |
| Named single-family homes | 50 |
| **Total for 50 named homes** | **668 credits** |
| Named rate | 50 / 52 = 96% |
| Disc proven complete by the scan | ≈ 300 m around the center |

Rebuilt from the saved recordings on 2026-11-22: same 53 answers, same 50
homes, 0 network, 0 new credits (`functions/test/pilot.test.js`).

## 2. Cost of one new area by named rate (sensitivity)

`credits = 200 + 9 × ceil(50 / rate)`, capped at 80 lookups (920).

| Share of looked-up addresses that end up named | Lookups | Credits | Named homes |
|---|---|---|---|
| 96% (pilot suburb) | 52–53 | 668–677 | 50 |
| 90% (planning default) | 56 | 704 | 50 |
| 75% | 67 | 803 | 50 |
| 62.5% | 80 | 920 | 50 |
| 50% (mixed / condo areas) | 80 (cap) | 920 | 40 |
| low (downtown, apartments, commercial) | 80 (cap) | 920 | few — the area may also run out of the 100 addresses |

## 3. Three architectures

- **A. Per-user area cache** (before 2026-11-22): one stored result per
  user per ~110 m grid key, 30 days.
- **B. Shared area-only cache**: one stored result per ~110 m key for all
  users, 30 days.
- **C. Shared area + canonical property cache + geographic index** (now
  implemented; shared mode needs Melissa's licence; per-user mode is the
  default): scans and property answers stored once, reused by any
  overlapping search.

### Users at the same spot (same neighborhood point)

| Users | A | B | C |
|---|---|---|---|
| 1 | 668 | 668 | 668 |
| 10 | 6,680 | 668 | 668 |
| 100 | 66,800 | 668 | 668 |
| 1,000 | 668,000 | 668 | 668 |

### Distance between users' points (second user; first already paid 668)

| Second user is… | A | B | C (fill, default) | C (prove nearest 50) |
|---|---|---|---|---|
| same spot | 668 | 0 | **0** | 0 |
| 50 m away | 668 | 668 (other key) | **0** (50 stored names reused; marked `partial`) | ≤ 524 (scan + ~36 lookups) |
| 200 m | 668 | 668 | **0** | ≤ 920 (upper estimate) |
| 400 m | 668 | 668 | **0** | ≤ 920 |
| 2 km | 668 | 668 | ≈ 704 (no overlap: cache miss) | ≈ 704 |
| 5 km | 668 | 668 | ≈ 704 | ≈ 704 |

Scenario figures for C come from the real pilot data
(`functions/tool/pilot_scenarios.js`, test "scenarios A–F").

### Users spread over a suburb (example, a model, not a measurement)

10 users 200 m apart along a street (0 – 1.8 km): A and B ≈ 6,680. C (fill)
≈ one scan per ~600 m of street → 4 areas ≈ 2,700–2,800. C depends on how
spread out users are; use the hit rate below.

### Sensitivity: share of new users whose spot already has ≥ 50 stored names (C)

`credits ≈ users × (1 − hit rate) × 668`

| Hit rate | 1 user | 10 | 100 | 1,000 |
|---|---|---|---|---|
| 0% | 668 | 6,680 | 66,800 | 668,000 |
| 50% | 334 | 3,340 | 33,400 | 334,000 |
| 80% | 134 | 1,336 | 13,360 | 133,600 |
| 95% | 33 | 334 | 3,340 | 33,400 |

(A has an effective hit rate of 0% across users; B helps only at identical
~110 m keys.)

### Repeated use (all architectures as implemented today)

| Action | Melissa credits | Firestore |
|---|---|---|
| App restart, tab switch, log in again, reinstall | 0 (cache) | ~61–101 reads per area load |
| Same spot next day | 0 | same |
| New prayer round (same 50 homes) | 0 | 3 writes (round docs + profile) |
| Each prayer | 0 | 2 writes (status + history event) |
| Same spot after 30 days | owner records expired: **nothing is refreshed automatically**; an authorized refresh = Property only if addresses may be kept longer (52 × 9 = 468), else full 668 | — |
| Setup preview / pin dragging | 0 (Overture only) | cell reads |

## 4. Firestore (Blaze) estimates

| Operation | Reads | Writes | Storage |
|---|---|---|---|
| Cache hit (complete, pilot) | 61 (1 scan query + 60 property reads) | 1 counter | — |
| Cache hit (overlap, partial) | ~101 | 1 | — |
| Paid new area | ~70 | ~60 (scan, ~52 properties, job, counters) | ≈ 50 KB per area |
| 1,000 areas stored | — | — | ≈ 50 MB |

Example: 1,000 users × 3 app opens a day ≈ 3,000 area loads × ~61 reads ≈
183,000 reads/day — about $0.06–0.11/day at current Firestore list prices
(check the current price list for the project's region; the first 50,000
reads/day are free). Storage of 50 MB is within the free 1 GiB.

## 5. Assumptions and limits

- Reverse GeoCoder returns the nearest deliverable addresses (apartments,
  undeliverable and empty lots off) and at most 100; in dense areas 100
  addresses may cover < 300 m.
- Coverage of a union of scans is sampled every 10 m (reported one step
  short).
- The prove estimate uses the stored address density (an upper estimate).
- Melissa may bill requests that timed out on our side; those are not in
  our estimate.
- Shared-cache figures require Melissa's written permission to show one
  stored record to several users.
