# Melissa-first neighborhood (property owners from public records)

> See [CACHE_DESIGN.md](CACHE_DESIGN.md) / [GEOSPATIAL_ALGORITHMS.md](GEOSPATIAL_ALGORITHMS.md) for the current design (2026-11-24).

> Superseded in part (2026-11-22 afternoon): discovery is now **cache first**
> (canonical property cache, coverage-aware nearest 50, one paid job per
> area, budgets). See `docs/MELISSA_CACHE_STRATEGY.md` and
> `docs/COST_MODEL.md`. Pilot result: 668 credits for 50 named homes.

Status 2026-11-22: **built and tested locally; OFF everywhere**. Nothing
deployed, no production data changed, Overture dataset kept as fallback.

## 1. What the account can do (checked 2026-11-22)

| Melissa product | Gives a list of properties near a point WITH owner names? | On this account |
|---|---|---|
| LeadGen Property API (`list.melissadata.net/v2/Property/count_*`, `buy_*`) | Yes: ZIP/address radius, property type (10 = single family), owner-occupied, owner names | **No**: both keys return status 116 "no permission to this service" (free count call) |
| Data Retriever Cloud API | No property endpoint (Business, Consumer, MAK, New Movers, New Homeowners only) | not tested |
| Reverse GeoCoder | Addresses only (no names, no home/business flag); max 100 records, max 10 miles | Yes, 2 credits per address returned |
| Property LookupProperty | One address (or Melissa Address Key) → recorded owner, property use, parcel | Yes, 9 credits per lookup |

Even if LeadGen Property were enabled, Melissa's Data Products terms make
such lists "Rental": one-time marketing use, internal only, not for display
to third parties (sections 6.1(a), Appendix A-3, "Internal Business
Purposes"). So the workable flow is **Reverse GeoCoder → Property**.

## 2. Flow (`discoverOwners` Cloud Function, `functions/src/owners.js`)

1. Reverse GeoCoder: up to 100 deliverable addresses nearest the point
   within `MELISSA_OWNER_RADIUS_MILES` (default 1), apartments excluded.
2. Free filters: units inside buildings and multi-unit buildings skipped;
   duplicates by Melissa Address Key.
3. Property LookupProperty **by Melissa Address Key**, nearest first, 4 at a
   time, until 50 named homes or `MELISSA_OWNER_MAX_LOOKUPS` (default 80).
4. Kept only if: Melissa found the parcel at the same address key (or same
   house number + ZIP), property use is residential, a recorded owner name
   exists, and the parcel was not already listed.
   - single family (Melissa codes 181, 306, 363, 364, 376, 384, 385, 390,
     452, 616, 618): always
   - condo / townhouse / co-op / mobile home: on (`includeCondos`)
   - apartments / multi-family: off (owner is usually a landlord)
   - commercial, industrial, exempt, vacant land: never
   - no use code: off
5. Result stored for `MELISSA_CACHE_DAYS` (per user; shared per area only
   if `MELISSA_OWNER_SHARED_CACHE=true`). Fewer than 50 → the real number.

App (`MELISSA_OWNERS=true`): `OwnerArea` shows only those named homes on
Home, Neighborhood, Prayer List and Follow-up. Card: owner name, "Property
Owner (Public Record) · <property use>", street, "CITY, ST ZIP · distance",
Pray chip; the details sheet adds "The owner may not live here." and the
Prayed / Visited / Invited / Follow-up actions. A name the user types still
wins. If Melissa cannot answer, the Overture homes are shown with the reason.

## 3. Credits per new area

| Step | Credits |
|---|---|
| Reverse GeoCoder, 100 addresses | 200 |
| Property, up to 80 lookups | up to 720 |
| **Per new area (max)** | **≈ 920** (reserved, unused given back) |
| Same area again (cache) | 0 |

How many of 80 lookups end up named residential depends on the area (not
yet measured on a residential area). Dense downtown: low (Chula Vista
downtown test: 1 of 2 checks matched, and it was commercial). Suburban
single-family streets: expected high. **The pilot measures this.**

Reaching 50: Reverse GeoCoder returns at most 100 addresses; after skipping
units and businesses, 50 named homes is likely in single-family suburbs,
unlikely in downtowns, apartment areas and rural areas (fewer addresses
within 1 mile). Raising `MELISSA_OWNER_MAX_LOOKUPS` above 80 or the radius
increases both reach and cost; Reverse GeoCoder cannot return more than 100.

Limits (server): 5 new areas per user per day, 2,000 credits per day
app-wide, 6 h pause after Melissa GE14 (out of credits).

## 4. Before production (needs approval)

1. **Melissa, in writing** (Property Cloud API): owner names may be shown
   to signed-in app users; results may be stored N days; one stored result
   may be shown to several users (shared cache); the use is not FCRA.
2. Client: enable APIs and grant roles (`docs/DEPLOY_FUNCTIONS.md`).
3. Deploy `discoverOwners` with `MELISSA_OWNER_DISCOVERY_ENABLED=true`,
   `MELISSA_ALLOW_OWNER_NAMES=true` (only after 1).
4. App build with `--dart-define=MELISSA_OWNERS=true`.

## 5. Local testing without spending credits

The Functions emulator saves every real Melissa response in
`functions/.melissa-recordings/` (git-ignored; holds real owner data) and
replays it for free. With `MELISSA_REPLAY_ONLY=true` (in
`functions/.env.local`) an unrecorded request fails instead of calling
Melissa. Tested: 13 backend tests (Melissa-format responses + real saved
responses), 6 app tests, and the emulator call on replayed real responses
(White House: 1 address, 1 lookup, excluded as non-residential → 0 named;
unrecorded area → no call, nothing charged).

## 6. Proposed pilot (needs approval)

One residential area chosen by the client, real calls on the local
emulator only, recorded for free replays afterwards:

- up to 100 × 2 + 80 × 9 = **920 credits maximum** (one area)
- report: addresses found, lookups, named single-family, condos, excluded
  (commercial / no owner / mismatch / not found), credits actually used
- real names stay on the developer's machine (not published) until item 1
