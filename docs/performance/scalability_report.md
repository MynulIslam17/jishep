# Firestore scalability — report (2026-11-10)

Measured numbers are in [geo_benchmark.md](geo_benchmark.md) (regenerate:
`flutter test --tags benchmark`). Reads there are exact billed-read counts of
the app's query engine against an in-memory model of the Firestore cell query
(checked against `fake_cloud_firestore` in `test/geo_search_test.dart`).
**Not measured:** device latency, frame times, memory on a real phone.

## Problems found

| Area | Before | Effect at 100k households |
|---|---|---|
| Home / Neighborhood geo load | geoflutterfire `fetchWithin`: whole geohash cell + 8 neighbours at the precision of the range, then sorted and cut to 200 | 5 km range: **100,005 reads per load**; households past the first 200 silently missing |
| Status listener | `watchStatuses`: live listener on **every** status the user ever made | grows forever; full re-download on every app start |
| Follow-up tab counts | derived from that full listener | needed the unbounded listener |
| Notifications | live `limit(100)` + unbounded unread listener | 100 docs per open; unread listener unbounded |
| Mark all read / clear all | read all matching docs into memory at once | unbounded memory |

## What changed

- `lib/core/data/geo_search.dart` (new): progressive nearest-first search.
  Reads circles outward (adaptive radius from observed density), splits dense
  cells, resumes with cursors; nothing nearer than `coveredMeters` can be
  missing, no document is read twice, obsolete searches are dropped.
- `HouseholdRepository`: `fetchCell`, `geoSearch`, `fetchStatuses` (ids in
  chunks of 30), `watchStatusChanges(since)` (this session only),
  `countStatuses` (5 `count()` aggregates). `fetchWithin`/`watchStatuses`
  removed.
- `HouseholdStore`: loads the nearest 25 (largest Home count); statuses only
  for loaded households; lifetime and tab totals from `count()` with local
  deltas; `loadMoreArea` for Neighborhood paging; `isNearHome` is tri-state.
- Neighborhood: reads the next page from Firestore one page ahead of the
  scroll; "N+ in range" until the whole range is read.
- Home badge "N+ in range"; Location setup preview reads the nearest 200
  ("200+").
- Follow-up: still 20 per page; pages share their statuses with the store;
  tab counts from server totals.
- Notifications: live newest 30, older pages by cursor ("Show older" /
  scroll), unread badge listener capped at 100 ("99+"), batch operations in
  chunks of 450. Items pushed out of the live page are kept.
- `geoflutterfire_plus` moved to dev dependencies (tests only).
- `tool/seed_scale/`: emulator-only deterministic seeding and cleanup.

## Reads per screen open (100k households, from the benchmark)

| Scenario | Before | After |
|---|---:|---:|
| Home load, 5 km, dense area | 100,005 | 477 |
| Home load, 5 km, medium area | 100,005 | 132 |
| Home load, 5 km, sparse area | 100,005 | 110 |
| Whole 5 km range (scroll to the very end), dense | 100,005 (and only 200 shown) | 57,561, all 54,745 shown |
| Statuses at sign-in (user with 3,000 statuses) | 3,000 + live | ≤ households loaded + 5 count reads |
| Notifications open | 100 + all unread | 30 + ≤ 100 unread |

All 24 benchmark cases matched brute force exactly; 0 documents read twice.

## Indexes and rules

- **No new indexes needed.** `geo.geohash` range + orderBy, `updatedAt >=`,
  `isRead ==` + limit and `count()` with one equality use automatic
  single-field indexes; Follow-up composites were deployed earlier.
- **Rules unchanged** (12/12 rules tests pass). `count()` is allowed by the
  existing owner read rule.
- Nothing was deployed and no production data was written.

## Tests

- `flutter test --exclude-tags benchmark`: 205 passed. `flutter analyze`:
  no issues. Rules: 12/12.
- New/updated: Neighborhood progressive paging (all 40 once, nearest first,
  40 reads), page-waiting, bounded status reads (500 remote statuses → reads
  only loaded ids; totals 501 / 251 / 100 from counts), Follow-up server
  counts and change listener, Location setup "200+", notification paging,
  live arrival without gaps/duplicates, unread cap, batched mark/clear.

## Risks / not done

- No real-device latency or frame measurements; run the app against the
  seeded emulator (see `tool/seed_scale/README.md`) to profile.
- Dense hotspots: the first page can cost ~480 reads at 100k (Old Dhaka
  density); fine for cost, worth watching.
- Status deletions on another device are not seen live (the app never
  deletes statuses except on account deletion).
- A notification deleted on another device stays in loaded older pages
  until pull to refresh.
- Follow-up "Outside your neighborhood" shows only when known (no extra
  reads to find out).
