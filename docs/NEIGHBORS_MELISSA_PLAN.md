# Neighbors: Overture + Melissa (decision, status, deployment)

Date: 2026-11-21. Target project: `gps-para-el-cielo`. `gps-cielo` is not
changed by anything here.

## 1. Evidence

### Overture (what the app uses today)
- `cells/{prefix}` hold **address points** (not buildings) from Overture
  `theme=addresses`, one gzipped document per 5-char geohash (split finer
  when > 4,000 points). Built by `tool/overture_cells/build_cells.py`.
- The 50,737 cells in `gps-cielo` are exactly **California (41,059) + New
  Jersey (9,678)**, 17.1 M address points. `gps-para-el-cielo` has 1,496 of
  them.
- Each apartment unit is its own record (`APT 4B`); a building record
  without units is dropped when its units exist. Duplicates at the same point
  are removed.
- The app (`CellArea`) reads the 3×3 block of cells around the chosen point
  (about ±5 km), then the 5×5 ring once (about ±12 km) if fewer than 50, and
  keeps the 50 nearest by distance. No household is invented; fewer than 50
  shows the real count; no cell = "This area isn't available yet".
- **Overture has no residential flag**: commercial addresses are included.
- **Nationwide coverage (measured 2026-11-21, release 2026-10-21.0):**
  126.3 M US points in 49 of 52 areas. **Missing: Hawaii, New Hampshire,
  Puerto Rico.** Very sparse vs. real housing: NV 28 k, SD 86 k, SC 212 k,
  GA 653 k, MI 869 k, PA 1.16 M. Good: CA 13.8 M, FL 12.3 M, TX 12.1 M,
  NY 6.5 M, NC 6.1 M, OH 5.5 M and most others.
  (Counts: `scratchpad state_counts.py`, Overture public S3, 2 columns.)

### Melissa (official docs; live test still pending, see §4)
| Product | Finds addresses near a point? | Home/business | Names | Cost |
|---|---|---|---|---|
| Reverse GeoCoder | **Yes**: up to 100 nearest within 10 mi | No | No | not published |
| Personator Check | No (needs an address) | Yes (DeliveryIndicator R/B/U), rooftop geocode | not with Check | 3 credits |
| Global Address Verification | No | Yes | No | 10 credits |
| Property LookupProperty | No | Property use | **Owner** name | 9 credits |
| Personator Append | No | — | Resident name | **GE29 on a credit license** (documented) |
| Personator Search | No (person search) | — | Yes | not published; "not intended for skip tracing" |


### Melissa live test (2026-11-21, credit license, public buildings only)
Keys: `~/.config/gps-cielo/melissa.env` (outside the repo, mode 600).
Balance 1,000 → 954 (46 credits). Measured prices:

| Product | Works on credit key | Credits | What came back |
|---|---|---|---|
| Reverse GeoCoder | Yes | **2 per address returned** | address, ZIP, lat/lon, distance, MAK; no residential flag |
| Personator Check | Yes | 3 | AS01 verified, DeliveryIndicator (R/B/U), rooftop (GS05); name/phone/email empty |
| Global Address Verification | Yes | 10 | formatted address, DeliveryIndicator, lat/lon |
| Property LookupProperty | Yes | 9 | use group, year built, lot size, parcel lat/lon, APN, assessed value, **recorded owner name** |

- The free Usage API returns `GE02`, 0 services for both keys, so it cannot
  list products for this account.
- Resident names (Personator Append): **subscription key returns GE21
  "Append not activated"** (tested 2026-11-21, public building). Resident
  data is not available on this account unless Melissa activates Append.
- Melissa discovery cost: 50 homes ≈ 100 credits (Reverse GeoCoder) + 150
  (Personator Check to drop businesses) ≈ 250+ credits per neighborhood.
- Real responses are kept as test fixtures in `functions/test/fixtures/`.

Terms found (Data Products T&C): no redistribution without a Duplication
License; internal business use; **no FCRA use**. Cloud-API caching terms were
not found — must be confirmed with Melissa in writing.

## 2. Decision: Architecture C (hybrid)

- **Discovery stays on Overture cells** (free per lookup). Melissa-only would
  need 1 Reverse GeoCoder call + a residential check on 50–100 addresses
  (150–300+ credits) per neighborhood: 1,000 credits ≈ 3–6 neighborhoods.
- **Melissa enriches one household at a time, on request**, through the
  `enrichHousehold` Cloud Function (Personator Check, 3 credits): verified
  address, residential/business, rooftop location. Per-user and app-wide
  daily budgets; results stored only for the user who asked.
- **No resident or owner names from Melissa** until (a) the subscription
  license includes them and (b) Melissa confirms in writing that showing them
  in this app is allowed. Names stay user-entered and private (existing
  `residentName`, owner-only).
- **Gaps (HI, NH, PR, sparse states):** candidate fallback is Melissa Reverse
  GeoCoder, *only after* its credit price and caching terms are confirmed.
  Not built yet.

## 3. Implemented (this branch)

| Item | Files | Status |
|---|---|---|
| US-only location search incl. state, county, ZIP | `lib/core/services/address_suggestion_service.dart` | Implemented, tested |
| Setup: "Where do you want to pray?" (home or any US area) | `lib/features/auth/presentation/pages/location_setup_screen.dart` | Implemented, tested |
| Prayer focus (chips or own words, optional) | `location_setup_controller.dart`, `user_model.dart`, `auth_service.dart` | Implemented, tested |
| Rules: `prayerIntention`; `users/{uid}/enrichment` read-only; `melissa_usage` server-only | `firestore.rules`, `tool/firestore_rules_test/rules.test.js` | Implemented, tested (emulator), **not deployed** |
| Backend `enrichHousehold` (validation, budgets, cache, retries, GE14 pause, no PII in logs) | `functions/src/*.js`, `functions/test/*.js` | Implemented, tested (emulator + fake Melissa), **not deployed** |
| App "Check address" tile (flag `ADDRESS_CHECKS`, off) | `lib/core/services/address_check_service.dart`, `lib/shared/widgets/household/address_check_tile.dart` | Implemented, tested |
| Melissa capability probe | `tool/melissa/probe.js` | Ready; **blocked** (no key file) |

Tests: Flutter 391 pass; rules 16 pass; functions 20 pass. All Melissa
responses in tests are hand-written fixtures in the documented shape, not
live data.

## 4. Pending / approvals

1. **Melissa keys** → `~/.config/gps-cielo/melissa.env`, then
   `node tool/melissa/probe.js usage` (free) and
   `node tool/melissa/probe.js paid --yes` (≤ 4 records per working key,
   public test address: US Capitol).
2. **Client IAM on gps-para-el-cielo** (blocked today: no
   `serviceusage.services.use`): enable Cloud Functions, Cloud Build,
   Artifact Registry, Cloud Run, Secret Manager APIs; grant the developer
   Editor (or Service Usage Consumer + Cloud Functions Admin + Secret Manager
   Admin + Service Account User).
3. **Deploy (approval required):**
   - `firebase deploy --only firestore:rules --project gps-para-el-cielo`
     (must go out **before** an app build that saves `prayerIntention`).
   - `firebase functions:secrets:set MELISSA_CREDIT_LICENSE --project gps-para-el-cielo`
   - `firebase deploy --only functions --project gps-para-el-cielo`
   - then build with `--dart-define=ADDRESS_CHECKS=true`.
4. **Cell migration (approval required):** copy the remaining 49,241 CA+NJ
   cells to gps-para-el-cielo with `seed_firestore.js` (re-pointed at the new
   project; never overwrites matching docs). ≈ 49 k writes ≈ $0.09.
   Nationwide build: ≈ 126 M points ≈ 4.8 GB ≈ 400 k docs ≈ $0.75 writes +
   ≈ $0.70/month storage (Blaze). Overture data licenses are per source
   (mostly open/public domain); attribution "© Overture Maps Foundation" is
   already shown.
5. **Melissa written confirmation:** caching (default 30 days per user;
   `MELISSA_CACHE_DAYS=0` disables), Reverse GeoCoder price, and whether
   owner/resident names may be displayed.
6. **App Check:** `ENFORCE_APP_CHECK=true` after App Check (DeviceCheck /
   Play Integrity) is registered for both apps.

## 5. Cost per neighborhood (estimates)

- Discovery: 0 Melissa credits; 9–25 cell reads the first time (cached on
  device afterwards) ≈ $0.00001.
- Optional check per opened household: 3 credits (+1 read, 1–3 writes).
- Defaults: 20 checks per user per day, 150 credits per day app-wide.

## Status 2026-11-21: gap-filler built locally, OFF

- `discoverNearby` (Reverse GeoCoder, 2 credits/address) fills only when
  Overture has fewer than 50 homes. It is off on the server
  (`MELISSA_GAP_FILL_ENABLED=false`) and in the app (`MELISSA_GAP_FILL`).
- Limits: 3 fills per user per day; 300 credits per day app-wide; unused
  credits are given back to the counters; 6 h pause after GE14.
- Per-user cache only (`users/{uid}/gap_areas`), 30 days; set
  `MELISSA_CACHE_DAYS=0` if Melissa's terms do not allow it.
- Melissa homes are labelled "Address from Melissa (not in Overture data).
  Home or business not verified." No names anywhere.
- Deployment steps, APIs and IAM roles: see `docs/DEPLOY_FUNCTIONS.md`.
- Tests: functions 44, rules 16, Flutter 402, all passing; Functions
  emulator smoke test passing (found and fixed an App Check flag bug).
