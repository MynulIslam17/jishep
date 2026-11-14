# Neighbors: Households from Overture + Resident Names

## Goal
Show real US households (homes/apartments) near the user's location, without a
paid data vendor, and let the user add the name of the people who live in a
household. Runs on the free Firebase **Spark** plan (no card).

## Scope — IMPORTANT
- IN SCOPE: (A) household data from Overture, stored as gzipped cell
  documents in Firestore, (B) adding/editing/removing a resident name on a
  household.
- OUT OF SCOPE: do NOT change the existing prayed / visited / invited /
  follow-up / notes UI or logic, the map design, onboarding, Settings, or any
  other screen, except the small additions listed in section 4.
- No Cloudflare R2 or other paid/external storage.

## Spark limits to design around
| Limit | Value | What it means here |
|---|---|---|
| Stored data | 1 GiB | California (~490 MB) + New Jersey fit; the whole USA (~4.7 GB) does **not**. |
| Writes | 20,000 / day | Seeding is spread over days (California ≈ 41k docs ≈ 3 days). |
| Reads | 50,000 / day | A first visit to an area reads ~9 cell docs; revisits read 0 (device cache). |
| Document size | 1 MiB | A cell file must be ≤ 900 KB gzipped (build fails otherwise). |

## 1. Current code (already built — read before changing)
- Home location: `LocationSetupController` → Photon (OSM) → `users/{uid}`
  (`latitude`, `longitude`, `address`, `searchRadiusKm`, `radiusHomes`).
- Households: Firestore `households/{id}` with `geo: {geohash, geopoint}`,
  seeded by `tool/seed_households/seed.js`, read-only in `firestore.rules`.
  (140 `demo_bd_*` test households in Bangladesh — do not delete without
  asking.)
- Search: `GeoSearch` (`lib/core/data/geo_search.dart`) grows geohash circles
  nearest-first; uses `HouseholdRepository.fetchCell(prefix)`.
- Store: `HouseholdStore` builds `households`, `areaHouseholds`,
  `homeHouseholds`; per-user flags in
  `users/{uid}/household_status/{id}`.

## 2. Part A1 — Data pipeline (`tool/overture_cells/`, Python + DuckDB)
1. Read Overture `theme=addresses/type=address` GeoParquet directly from its
   public S3 bucket (no login/key). Filter `country = 'US'`. Support
   `--bbox` / `--state`. State = `address_levels[1]`. City = `postal_city`
   (mailing city) when set, else `address_levels[2]` after its last comma
   (NJ stores "County, Municipality" there, e.g. "Essex, Newark").
2. Keep: `id`, lat, lon, `number`, `street`, `unit`, `postcode`, city, state.
   `label` = "<NUMBER> <STREET>" + " APT <UNIT>" if unit (unless the unit
   already starts with APT/UNIT/STE/#…), upper-case. Skip points without a
   house number and street.
3. Drop a building record (no unit) when records with the same house number
   + street (same state; same ZIP when both have one) have units.
4. Missing city/ZIP: copy from another address at the same point, else from
   the nearest address within 100 m that has both; else leave missing.
5. 9-char standard base32 geohash per point, identical to `geofire-common`
   (tested in `test_geohash.py`).
6. Group by first 5 geohash chars. A group with > 4000 points is split into
   p6 children (recursively, p7…), with a stub for the split cell.
7. Files: `out/<area>/cells/<prefix>.json.gz`
   `{"v":"<release>","p":"9mudq","h":[{"i":"<id>","a":lat,"o":lon,"g":"<geohash9>","l":"<label>","c":"<CITY, ST>","z":"<zip>"}]}`
   Stub: `{"v":"<release>","p":"9mudq","split":6}`. No file = no addresses.
   `meta.json`: `{"release":"...","cellPrecision":5,"maxPerFile":4000}`.
   **The build fails if any `.json.gz` is larger than 900 KB.**
8. Report: points, Firestore doc count, total size, largest file, bytes per
   point.
Build order: Spring Valley test bbox → New Jersey → California.

## 3. Part A2 — Firestore storage and app source

### 3.1 Data model
```
cells/{prefix}          one document per cell file
  v: string             Overture release, e.g. "2026-10-21.0"
  h: Bytes              the .json.gz file content, unchanged
  n: int                number of households
  split: int            only on stub docs (same meaning as the stub file)
```
`firestore.indexes.json` field overrides disable indexing on `cells.h`,
`cells.v`, `cells.n`, `cells.split` (no queries on cells, only `get()` by id).

Rules (added; everything else unchanged, `household_status` stays private):
```
match /cells/{id} { allow read: if request.auth != null; allow write: if false; }
```

### 3.2 Seed script `tool/overture_cells/seed_firestore`
- Reuses the auth setup of `tool/seed_households` (gcloud login → Firestore
  REST; project `gps-cielo` only, `cielo-63925` refused).
- Writes `cells/{prefix}` from an `out/<area>/cells` folder, 400 docs per
  batch.
- Resumable: progress file in `out/.seed_progress/` (outside the build
  output, which a rebuild deletes) with a hash of each file. A doc whose
  file changed since it was written is rewritten. Docs not in the progress
  file are skipped when `v` and `n` already match in Firestore;
  `--rewrite` doesn't trust that match (use it after a rebuild when the
  progress file was lost).
- Requests are at most 8 MiB (Firestore limit 10 MiB per request).
- `--max-writes` (default 18000) to stay under the daily quota; stops cleanly
  and prints how many remain.
- Dry-run by default; `--emulator` targets the local emulator.
- Never deletes the old Bangladesh test data without asking.

### 3.3 App: `FirestoreCellSource` → `GeoRecord`
1. `GeoRecord` (id, lat, lng, geohash, label, cityStateZip) is the common
   type; the Firestore `households` source and the cell source both convert
   to it. `HouseholdModel` is built from a `GeoRecord` + the status doc.
2. Encode the user's point to a 5-char geohash; load that cell plus its 8
   neighbours, and for stubs (`split`) the child cells that are needed. Only
   prefixes of length ≥ 5. A loaded cell is complete (no paging / splitting
   in `GeoSearch`).
3. `get()` only, never snapshot listeners. A cell is read from the device
   cache first (Firestore's offline persistence keeps every document read),
   then from the server; decoded cells are also kept in memory. Reopening
   the screen costs 0 reads. Cells found missing are remembered for 24 h
   (they may be seeded later), so an uncovered area costs at most 25 reads
   a day. Children of split cells are read 4 at a time, nearest first, only
   while they can still hold one of the nearest 50.
4. Unzip, compute distances, sort, take the nearest 50.
   **Range rule:** start with the 3×3 block of p5 cells around the user
   (about ±5 km). If it holds fewer than 50 households, expand **once** to
   the 5×5 block (the ring around it), and no further. The cell source
   ignores the Settings range (`searchRadiusKm`); see 3.4.
5. Merge with `users/{uid}/household_status` (name, prayed, follow-up, …)
   by household id.
6. No cell document at all → show "This area isn't available yet" instead
   of "0 households".
7. The app's Dart geohash encoder uses the same boundary rule as
   `geofire-common` (`>`), with a test.
8. Feature flag `FeatureFlags.useCellHouseholds` (off by default; run with
   `--dart-define=USE_CELL_HOUSEHOLDS=true`); keep the `households` source
   until verified. Existing `household_status` docs use old seeded IDs: check in
   step 5 and ask before any migration.

### 3.4 Neighborhood size (decision: follow BLESS)
"My neighborhood" is **the nearest N homes**; with cell households the user
does not choose a distance. Rounds, the daily goal and "Round complete!" are
unchanged; a round is the N homes.
- **N** = `users/{uid}.radiusHomes`, Settings › Prayer preferences › "Homes
  in my neighborhood": 5, 10, 15, 20, 25 or **50**
  (`SearchRange.options`; `SearchRange.maxHomes` = 50 = `CellArea`'s
  nearest 50). New accounts get **50** (`SearchRange.defaultHomes`);
  existing accounts keep their saved value. A missing value also reads
  as 50.
- **km range** (`searchRadiusKm`): with `USE_CELL_HOUSEHOLDS` on
  (`SearchRange.userChoosesRange` false) it is hidden in Prayer
  preferences and first-run setup, and no label says "within X km"
  (Profile summary "Nearest 50 homes", Home map "Nearest 50 homes", empty
  states). The field and the `households` code path are kept: with the flag
  off everything works as before (range + count).
- **First-run setup** previews the real neighborhood: the nearest N homes
  (not "up to 200 in range"); the days-per-round line uses N. With the flag
  on the range step is skipped and the default 50 is used.
- The Home count slider moves one stop per option (the options are not
  evenly spaced).
- Reading up to 50 households up front (Home / Prayer List) instead of 25
  costs at most 25 more document reads per search on the `households` path;
  the cell path reads the same cells as before.

## 4. Part B — Add a resident name to a household
Households start without names. The user adds the name of the people living
there after meeting them. Names are PRIVATE to that user.

Data: `users/{uid}/household_status/{householdId}.residentName: string?`
(trimmed, max 120 chars). Written **only when the user sets one**; existing
"Resident" and "Demo Household NNN" values count as no name. Write with
merge; don't touch other fields. `hasSameStatusAs` includes the name.

UI — minimal additions only:
1. Wherever a household title is shown: `residentName` if set, else
   "Neighbor"; the address label stays as the subtitle.
2. In the existing household detail sheet: "Add name" / "Edit name" → small
   dialog with a text field, Save, "Remove name". Empty = removed.
3. No new search UI (Follow-up search already matches the name).
Optimistic local update, then Firestore write; the existing status listener
syncs other devices.

Implemented: `HouseholdModel.residentName` is `String?` (cleaned by
`HouseholdModel.cleanName`), `displayName` gives the name or "Neighbor".
`toStatusFirestore()` no longer includes the name; `saveStatus(...,
nameChanged: true)` writes it (or deletes the field when removed). The
"Add name / Edit name" item is in `HouseholdDetailBottomSheet`
(`ResidentNameDialog`); every screen saves through
`HouseholdStore.saveHousehold`. The old `households` docs' `residentName`
placeholders are no longer used.

Rules: keep the existing `household_status` rules; only change
`optString('residentName', 200)` to `optString('residentName', 120)`.

## 5. Acceptance
1. Spring Valley, CA: nearest households with correct address labels,
   ordered by distance.
2. Count 5→50 needs no network; revisiting an area costs 0 reads (cache).
3. Unnamed household shows "Neighbor" + address. Adding a name shows it in
   every list; it syncs to my second device; a second user at the same area
   still sees "Neighbor".
4. Removing the name returns to "Neighbor".
5. Prayed / follow-up / other existing features work exactly as before.
6. An area without cells shows "This area isn't available yet".
7. No secrets in the repo; daily reads/writes stay within Spark limits.
8. Credits text in the About sheet: "Address data © Overture Maps
   Foundation".

## 6. Order of work
1. Read the code; summarize; list mismatches. ✅
2. Part A1 for Spring Valley (local). ✅
3. Firestore design: spec, index overrides, rules, 900 KB check. Build New
   Jersey, finish California; show reports. **STOP.**
4. Seed script; seed New Jersey into the emulator; show counts. **STOP.**
5. Ask before seeding production (quota: ≤ 18k writes/day).
6. App source (`FirestoreCellSource`, cache, flag, 3×3 → 5×5 range rule)
   + unit tests.
7. Part B (resident name) + rules change.
8. Go through section 5: what passed, what to test by hand.

## Known issues
- **Old app builds and a 50-home neighborhood** (accepted for now).
  Builds from before 3.4 offer 5–25 homes and read a saved
  `radiusHomes = 50` as 25 (`SearchRange.normalize`). No crash: sliders and
  labels show 25, and the rules allow 1–200. It only matters when one user
  runs an old and a new build at the same time (e.g. two devices):
  - saving Prayer preferences on the old build writes `radiusHomes: 25`
    back, so the new build also drops to 25;
  - the old build's round is the nearest 25; once those are prayed for it
    shows "Round complete!" and the next day starts a new round
    (`users/{uid}.prayerCycleStartedAt`) for every device, before the new
    build's other 25 homes were prayed for.
  The app has no minimum-version / force-update check, so this cannot be
  blocked from the server today. Fix later with a minimum supported version
  if it shows up in practice.

## Open questions
- The whole USA does not fit in 1 GiB; choose which states to load.
