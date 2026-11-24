# Nationwide Overture cells: audit, estimate and checklist

> See [CACHE_DESIGN.md](CACHE_DESIGN.md) / [GEOSPATIAL_ALGORITHMS.md](GEOSPATIAL_ALGORITHMS.md) for the current design (2026-11-24).

Scope: keep the existing Firestore `cells/{prefix}` + Overture + Melissa
design and scale it to the whole US. No new architecture. (2026-11-22)

## 1. What the existing code already does (verified)

| Requirement | Where | Status |
|---|---|---|
| Geohash-5 indexing | `cells/{5-char prefix}`; `cellPrecision = 5` in `lib/core/data/cell_source.dart`; built by `tool/overture_cells/build_cells.py` | Yes. A cell with more than 4,000 homes becomes a *stub* (`split: 6`) plus one doc per non-empty 6-char child (rarely 7). |
| 3×3 then 5×5 lookup | `CellArea._load` + `blockCells(…, 1)` / `blockCells(…, 2, ringOnly: true)` | Yes. The 5×5 ring is read only when the 3×3 block has fewer than 50 homes. |
| Nearest 50 | `CellArea.maxHouseholds = 50`; user setting 5–50 | Yes |
| Split children read only when useful | `_collect`: children nearest-first, only while closer than the current 50th home | Yes |
| Duplicate removal | Build: same label at the same point kept once; building row dropped when its units exist. App: by record id. Gap-filler merge: same normalized address or same number within 30 m. | Yes |
| Distance sorting | haversine, sorted, `distanceOf(id)` | Yes |
| Apartments / units | Build writes `APT <unit>` (keeps `STE`, `#`, `UNIT`…); each unit is its own home; merge keeps different units apart (tested) | Yes |
| Caching | Memory LRU (32 cells) → Firestore device cache (0 reads) → server; missing cells remembered 1 day | Yes |
| Melissa enrichment (optional) | `functions/src/enrich.js` (Personator Check + Property), `discover.js` (gap-filler), behind flags | Yes, not deployed |
| Auth, Prayer List, Follow-up | Unchanged by any of this (402 Flutter tests pass) | Yes |

## 2. Firestore limits and how the cells stay inside them

| Limit | Firestore | Cells |
|---|---|---|
| Document size | 1 MiB | Build fails above 900 KB; the 4,000-home cap keeps the largest real file at **151 KB** |
| Batch write | 500 writes | 400 per batch |
| Request size | 10 MiB | ≤ 8 MiB per request |
| Index entries | values > 1,500 bytes are truncated | `h`, `v`, `n`, `split` are exempt from indexing (`firestore.indexes.json`), so there is no index storage or write cost |
| Write rate on a new collection | ramp up ("500/50/5"); sequential IDs can hot-spot | Import in region batches. The script waits for each request before sending the next |
| Reads | billed per doc, missing docs too | App reads only by ID (`get`), never queries or listeners |

## 3. Nationwide size (measured from Overture, not guessed)

Counted directly from Overture release **2026-11-18.0** (US addresses
with a house number and street), using the same 4,000-home split rule. The
estimator matches the real builds within 1–2%: California estimated 40,640
docs vs 41,059 built; New Jersey 9,494 vs 9,678.

| | California (built) | New Jersey (built) | **Whole US (estimate)** |
|---|---:|---:|---:|
| Addresses (homes + units) | 13.5 M | 3.7 M | **125.5 M** |
| Geohash-5 cells with data | ~11.8 k | ~1.2 k | **246 k** |
| Firestore docs (incl. stubs) | 41,059 | 9,678 | **≈ 500 k** (496 k + 2%) |
| gz payload (≈ storage) | 491 MB | 135 MB | **≈ 4.8 GB** |
| Local build files | 587 MB | 155 MB | ≈ 5.5 GB (208 GB free on this Mac) |

**Already in Firestore:**
- `gps-cielo`: California + New Jersey complete (50,737 docs).
- `gps-para-el-cielo` (client): 1,496 cells from the earlier, cancelled
  copy.

**Overture coverage is uneven.** Addresses per state, compared with
approximate Census housing-unit counts:

| Coverage | States |
|---|---|
| Good | CA 13.6 M, FL 12.2 M, TX 12.1 M, NY 6.5 M, NC 6.1 M, OH 5.5 M |
| Thin | PA 1.2 M (≈ 5.8 M housing units), MI 0.86 M (≈ 4.6 M), GA 0.65 M (≈ 4.5 M), LA 0.54 M (≈ 2.1 M), SC 0.21 M (≈ 2.4 M), SD 86 k (≈ 0.4 M), **NV 28 k (≈ 1.3 M)** |
| None | **Hawaii**, Puerto Rico |

In those areas the app shows fewer than 50 homes (honestly), until the
Melissa gap-filler is approved. Overture adds sources every month, so a
re-import later fills more.

### Docs per region (geohash-2), for importing in waves

| Region | Area (roughly) | Docs | Size |
|---|---|---:|---:|
| `dn` | TN, KY, NC, VA west, AL/GA north | 54 k | 609 MB |
| `dp` | OH, IN, IL east, MI, PA west, WV | 50 k | 572 MB |
| `dr` | NY, NJ, New England, PA east | 47 k | 668 MB |
| `9v` | TX east/central, LA, MS west | 46 k | 433 MB |
| `9y` | OK, KS south, MO, AR | 35 k | 236 MB |
| `9q` | California central (LA–Sacramento), NV south | 33 k | 437 MB |
| `9z` | NE, IA, KS north, MN south, WI | 31 k | 159 MB |
| `dj` | FL north, GA/AL south, SC | 29 k | 315 MB |
| `dq` | VA, MD, DE, DC, NC east | 23 k | 300 MB |
| `c2` | WA, OR north, ID north | 20 k | 161 MB |
| `cb` | MN north, ND | 19 k | 69 MB |
| `dh` | FL south | 18 k | 262 MB |
| `9w` `9x` `9t` | NM, CO, WY, AZ, TX west | 52 k | 363 MB |
| `c8` `9r` `9m` `9u` | MT/ND west, OR + N. California, San Diego, TX south | 34 k | 195 MB |
| others (`b*` Alaska, `f*` Maine, `9p` `c0` `c1` `c4` `dx` `de`) | | 5 k | 25 MB |

## 4. Speed and read cost (benchmarked)

`CELL_BENCHMARK=1 flutter test test/benchmark/cell_benchmark_test.dart`:
the app's own `CellArea` on the real CA + NJ cell files. Full table in
`docs/performance/cell_benchmark.md`.

| 200 random homes as start points | Median | p90 | p99 |
|---|---:|---:|---:|
| Cold Firestore reads | 13 | 15 | 25 |
| Downloaded | 174 KB | 417 KB | 648 KB |
| Client CPU (decode + sort) | 14 ms | 30 ms | 43 ms |
| With a 100 ms network round trip | 0.22 s | 0.24 s | 0.57 s |
| Farthest of the 50 homes | 179 m | 3.9 km | 13 km |

- City, suburb and small town: 50 homes within 75–212 m, 9–19 reads.
- Empty desert: 25 reads, then the honest "fewer homes" result.
- Repeat visit to the same area: **0 reads** (device cache).
- 3 of 200 random start points found fewer than 50 homes (rural edges).

**Cost on the client's nam5 database.** These are list prices; check them
in the Cloud console.

| Item | Unit price | Estimate |
|---|---|---|
| Reads | ≈ $0.06 per 100 k reads; 50 k reads/day free | 100 k cold searches ≈ 1.3 M reads ≈ **$0.80** |
| Storage | ≈ $0.18/GiB-month; 1 GiB free | ≈ 5 GB ≈ **$0.75–1/month** |
| Import writes | ≈ $0.18 per 100 k writes | 500 k ≈ **$1 one-time**, plus about the same per full monthly refresh (only changed cells are rewritten) |
| Egress | — | about 174 KB per cold search; 100 k searches ≈ 17 GB ≈ $1–2 after the free 10 GiB |

## 5. Incremental import strategy (existing tools, no redesign)

Tools: `tool/overture_cells/build_cells.py` and `seed_firestore.js`.
New in `seed_firestore.js` (tested in dry-run only):

- `--project gps-para-el-cielo` targets the client project. Only
  `gps-cielo` and `gps-para-el-cielo` are allowed; `cielo-63925` is always
  refused. Progress files are kept per project.
- `--prefixes 9q,9r` imports only cells under those geohash prefixes. A
  stub and its children share a prefix, so they always go together.

Plan:
1. **Build once, nationally:**
   `build_cells.py --name usa` (about 1–2 h, about 5.5 GB). A national build
   has no cut edges. Per-state builds cut the cells on state borders (see
   the README), so state-by-state *building* would leave gaps along every
   border.
2. **Import by region:**
   `seed_firestore.js out/usa --project gps-para-el-cielo --prefixes <wave> --write --max-writes 100000`.
   - Suggested waves: (a) `9q,9m,9r,dr,dq` (California + the Northeast incl. NJ, about 140 k docs);
     (b) `dn,dp,dq,dj,dh`; (c) `9v,9y,9z,9w,9x,9t,9u`; (d) `c,b,f,9p,dx,de`.
   - Each wave is resumable and skips docs that already match, including
     the 1,496 cells already in the client project.
3. **Measured upload speed** from this Mac (the California run): about
   15 k docs in 27 min. The whole US is therefore roughly 12–15 h of upload,
   spread over several sittings. Running it from Cloud Shell would be much
   faster.
4. **Verify each wave:**
   - The dry-run shows 0 to go.
   - Spot-check a few cities in the app.
   - The miss cache (1 day) means areas imported later appear by the next
     day for users who looked earlier.
5. **Monthly refresh (optional):**
   - Rebuild with the new release, then re-run the same commands.
   - Only cells whose file hash changed are rewritten.
   - Cells that disappear are not deleted (the script never deletes).

## 6. Checklist

**Needs your approval (✋) or the client (🏢):**

1. 🏢 The client enables APIs and grants roles (`docs/DEPLOY_FUNCTIONS.md`
   §1). Without `serviceusage.serviceUsageConsumer` the CLI returns 403.
2. ✋ Deploy Firestore rules to `gps-para-el-cielo`:
   `firebase deploy --only firestore:rules --project gps-para-el-cielo`.
   - **Must happen before an app build with the prayer intention ships**:
     the current deployed rules reject the `prayerIntention` field.
   - Indexes are unchanged and already deployed.
3. ✋ Build `usa` locally. This is free and touches no Firebase project.
4. ✋ Import wave (a), then check in the app on a device pointed at the
   client project.
5. ✋ Import waves (b)–(d).
6. ✋ Melissa secret + `firebase deploy --only functions --project gps-para-el-cielo`,
   with `MELISSA_GAP_FILL_ENABLED=false`.
7. Optional, ✋ spending: turn on `ADDRESS_CHECKS`; later the gap-filler,
   for thin states, Hawaii and Nevada.
8. 🏢 App Check registration, then `ENFORCE_APP_CHECK=true`.
9. Melissa written answers on caching and names (needed before names or a
   longer cache).

**Not changing:** authentication, Prayer List, Follow-up, cell format,
app search code.

## 7. Actual nationwide build (2026-11-22)

`build_cells.py --name usa --memory 9GB --threads 4` (with `--resume` after two
out-of-memory stops; the heavy steps now run in 16 slices). Output:
`tool/overture_cells/out/usa` (git-ignored, 5.6 GB on disk).

| | Value |
|---|---|
| Overture release | 2026-11-18.0 |
| Addresses read / kept | 126,202,222 / **123,889,836** (18.3 M are apartment units) |
| Removed | 654,639 with no house number; 16,066 duplicates; 1,641,681 building rows replaced by their units |
| Firestore docs | **496,241** (488,006 data + 8,235 split stubs) |
| Size | 4.82 GB gz; about 4.86 GB as Firestore documents |
| Largest doc | 195 KB (`djqh3hg76`, one 7,512-unit building in a 9-char cell that can't be split further). Firestore limit: 1 MiB |
| Validation | `validate_cells.py`: **0 errors** (sizes, structure, geohash vs lat/lon, duplicate ids/labels) |
| Coverage | 49 states + DC + VI; each state 91.5–100% of the raw Overture count (the rest is dedup and building rows). Hawaii and Puerto Rico have no Overture data. |
| Missing city / ZIP | 4.8 M / 8.8 M homes (shown with the state only) |

Waves for `gps-para-el-cielo` (dry-run counts):

| Wave | `--prefixes` | Docs | Homes | Size |
|---|---|---:|---:|---:|
| 1 | `9q,9m,9r,dr,dq` (California + Northeast incl. NJ) | 120,851 | 39.7 M | 1.4 GB |
| 2 | `dn,dp,dj,dh` | 150,589 | 45.4 M | 1.6 GB |
| 3 | `9v,9y,9z,9w,9x,9t,9u` | 166,393 | 31.5 M | 1.2 GB |
| 4 | `c,b,f,9p,dx,de,9n,8` | 58,408 | 7.2 M | 0.28 GB |
| | **Total** | **496,241** | | |
