# Melissa cost control

Part of the [master blueprint](GPS_PARA_EL_CIELO_MASTER_BLUEPRINT.md).
Supersedes `COST_MODEL.md`. Cache: [CACHE_DESIGN.md](CACHE_DESIGN.md).

## 0. Current verdict (2026-11-24)

**Live paid discovery is BLOCKED and OFF.**

| Fact | Value | Source |
|---|---|---|
| Melissa balance | **10,250 credits**, Auto-Refill off (2026-11-24, Melissa dashboard; 250 on 2026-11-23) | read in the browser, no API call |
| Cost of one new 50-home area | ≈ **700–920** credits (pilot 668) | §3 |
| Real spend to date | ≈ **704 credits** (pilot 668 + single checks/tests) | project memory |
| Production switches | `MELISSA_OWNER_DISCOVERY_ENABLED=false`, `MELISSA_GLOBAL_DAILY_CREDITS=0`, `MELISSA_GAP_FILL_ENABLED=false` | `functions/.env.gps-para-el-cielo` |

The balance cannot pay for one new area, so the blueprint's bounded live
test (Phase 9) was not run. To unblock: buy credits, confirm the balance in
the Melissa portal, set a written test budget, then follow §6.

## 1. Credit estimates

| Product | Credits | Verified |
|---|---|---|
| Reverse GeoCoder | 2 per address **returned** | 2026-11-21 on the credit key (balance 1,000 → 954) |
| Property LookupProperty | 9 per lookup | 2026-11-21 |
| Personator Check (enrichHousehold) | 3 per check | 2026-11-21 |
| Personator Search | not licensed on either key (GE08) | 2026-11-23 — not used |

These are **estimates** (`REVERSE_CREDITS_PER_RECORD = 2`,
`PROPERTY_CREDITS = 9`, `CHECK_CREDITS = 3` in code). Melissa's own usage
report is the billing authority; compare monthly.

## 2. Protection layers (every paid path)

All paid endpoints — `discoverOwners`, `discoverNearby` (gap-fill),
`enrichHousehold` — reserve credits in a Firestore **transaction before any
Melissa request**, and give back what was not used afterwards.

| Layer | Env var | Code default | Production (`.env.gps-para-el-cielo`) |
|---|---|---|---|
| Owner discovery may spend at all | `MELISSA_OWNER_DISCOVERY_ENABLED` | false | **false** |
| App-wide daily credits, ALL endpoints together (`budget.js overGlobalLimit`; ≤0 or missing = nothing) | `MELISSA_GLOBAL_DAILY_CREDITS` | 0 | **0** |
| Owner credits per day | `MELISSA_OWNER_DAILY_CREDITS` | 2000 | 2000 |
| Owner credits per month (`melissa_usage/month-YYYY-MM`) | `MELISSA_OWNER_MONTHLY_CREDITS` | 20000 | 20000 |
| Per-request ceiling (lookups shrink to fit; scan alone too big → `request_budget`) | `MELISSA_OWNER_REQUEST_MAX_CREDITS` | 920 | 920 |
| Property lookups per discovery | `MELISSA_OWNER_MAX_LOOKUPS` | 80 | 80 |
| Paid discoveries per user per day | `MELISSA_OWNER_PER_USER_DAILY` | 5 | 5 |
| Verified account required (email verified or Google/Apple/phone) | `MELISSA_OWNER_REQUIRE_VERIFIED` | true | true (file; not yet deployed) |
| Client coordinates must be within X m of the pinned home | `MELISSA_OWNER_LOCATION_TOLERANCE_M` | 250 | 250 (file; not yet deployed) |
| Owner names may be served | `MELISSA_ALLOW_OWNER_NAMES` | false | true (owner's direction 2026-11-23) |
| Shared cache | `MELISSA_OWNER_SHARED_CACHE` | false | true |
| Freshness | `MELISSA_CACHE_DAYS` | 365 | 365 (file; deployed functions still 30) |
| Gap-fill may spend | `MELISSA_GAP_FILL_ENABLED` | false | **false** |
| Gap-fill per user/day, credits/day | `MELISSA_GAP_PER_USER_DAILY`, `MELISSA_GAP_DAILY_CREDITS` | 3, 300 | 3, 300 |
| Enrichment lookups per user/day | `MELISSA_PER_USER_DAILY_LOOKUPS` | 20 | 20 |
| Out-of-credits pause (after Melissa GE14) | `melissa_usage/state.outOfCreditsAt` | 6 h | — |
| **Kill switch** (no redeploy) | `melissa_usage/state.paidDisabled` | — | not set |
| One paid job per area | `discovery_jobs/{scope}_{geohash6}` lease 150 s | — | — |
| App Check (soft) | `MELISSA_REQUIRE_APP_CHECK` | true | not deployed (paid only with a valid token) |
| App Check (hard) | `ENFORCE_APP_CHECK` (deploy-time) | false | **false** (old builds have no token) |

No limit was raised by this blueprint. Raising any spending value needs the
project owner's written approval.

### Reservation and settlement (from `owners.js`)

```
reserveOwners(db, uid, now, cfg, credits):            # one transaction
  credits ≤ 0 or > perRequestMaxCredits     → request_budget
  read day, month, day/users/uid, state
  state.paidDisabled                        → paid_disabled
  state.outOfCreditsAt < 6 h ago            → out_of_credits
  user.ownerDiscoveries ≥ perUserDaily      → user_daily_limit
  day.ownerCredits + credits > dailyCredits
     or spentToday(all endpoints) + credits > globalDailyCredits → app_daily_limit
  month.ownerCredits + credits > monthlyCredits → app_monthly_limit
  increment day.ownerCredits, day.ownerDiscoveries, month.ownerCredits, user.ownerDiscoveries

reserved = (scanNeeded ? 100×2 : 0) + min(maxLookups, ⌊(920 − scan)/9⌋, needed) × 9
… Melissa calls; spent counts only processed requests (UNCHARGED errors excluded)
settleOwners(unused = reserved − spent)    # undo the discovery count if nothing was spent
```

Over a limit (or kill switch, or unverified) the caller gets the **stored
records with `limited: <reason>`** — no throw, no Melissa call, no retry
loop (test: three requests over the monthly limit → 0 calls,
`deniedBudget: 3`). App messages for these reasons never mention credits or
budgets (`OwnerDiscoveryService.messageFor`).

### Abuse resistance

| Attack | Blocked by |
|---|---|
| Script calls `discoverOwners` with arbitrary coordinates | server uses only the pinned home; far coordinates → `location_not_authorized` (counted `deniedSecurity`) |
| Delete/re-create profile with a new location | `primary_locations/{uid}` is pinned; rules lock lat/lon once set |
| Many new accounts | verified-account gate; per-user limits; app-wide daily + monthly caps (test: 5 farm accounts, cap holds) |
| Old app version | same server checks (coordinates sent = saved home → allowed) |
| Concurrent identical requests | one lease per area; others read the result |
| Retry after failure | stored answers reused; no lookup bought twice |

App Check and Auth are necessary but not sufficient; the budget transaction
is the hard limit. App Check: soft gate implemented locally, not deployed ([APP_CHECK.md](APP_CHECK.md)).

## 3. Cost of one new area

`credits = 200 + 9 × ceil(50 / namedRate)`, capped at 80 lookups (920).

| Named rate | Lookups | Credits | Named homes |
|---|---|---|---|
| 96% (pilot suburb) | 52–53 | 668–677 | 50 |
| 90% (planning default) | 56 | 704 | 50 |
| 75% | 67 | 803 | 50 |
| ≤ 62.5% | 80 (cap) | 920 | 50 or fewer |

Shared cache, users at the same spot: 1 → 668, 10 → 668, 1,000 → 668
(per-user caching would be 668 × users). Second user 50–400 m away: 0
credits in fill mode (stored names reused, honestly `partial`); 2–5 km away:
a new area (≈ 704). Cache hit-rate model:
`credits ≈ new users × (1 − hit rate) × 668`.

Repeated use costs 0 credits: restart, reinstall, other device, same spot
next day, new prayer round, marking prayers, setup preview / pin drag.

Firestore per cache hit ≈ 61 reads (pilot), overlap ≈ 101; paid area ≈ 70
reads + ≈ 60 writes; ≈ 50 KB stored per area.

## 4. Usage observability (`functions/tool/melissa_ops.js`)

```
node tool/melissa_ops.js status|report --project=<id> [--days=30] [--json]
node tool/melissa_ops.js kill|unkill  --project=<id> --reason="…" [--approve=<id>]
```

Counters in `melissa_usage/{day}` (counts only — no uid, address or name):

| Field | Meaning |
|---|---|
| `ownerCacheHits` / `ownerCacheMisses` | served complete from cache / incomplete |
| `propertiesReused` | stored property answers reused |
| `duplicatesAvoided` | same address from several scans merged |
| `overlapScansUsed` | scans combined in overlap answers |
| `successfulDiscoveries` / `failedDiscoveries` | paid jobs finished / stopped or failed |
| `ownerDiscoveries`, `ownerCredits` | reserved discoveries / net estimated credits |
| `estimatedCredits`, `melissaRequests`, `failedLookups` | spend detail |
| `deniedBudget` / `deniedSecurity` | refused by budget or kill switch / by location or verification |
| `ownerWaited` | joined another request's discovery |
| `credits`, `gapCredits` | enrichHousehold / discoverNearby credits |

The report adds the month total, cache hit rate, kill-switch state and
warnings at 80% of the daily or monthly limit or after an out-of-credits
answer. Local emulator report 2026-11-24 (30 days): 23 hits, 5 misses,
82.1% hit rate, 1 paid discovery (pilot, 679 net estimated), enrichment 48.
Note: the local month document shows 0 although the pilot day shows 679 —
the pilot's monthly counter is not in the emulator data (cause not
established). The daily documents are the reliable record for that day.

## 5. Kill switch

`kill` sets `melissa_usage/state.paidDisabled = true` (+ reason, operator,
time). Every reservation transaction reads it, so the next request of every
paid endpoint refuses (`paid_disabled`) without a redeploy; cached records
are still served. `unkill` clears it; env switches and budgets still apply.
Tested in `blueprint.test.js` and `ops_tools.test.js`.

## 6. Controlled activation (when unblocked — not done)

1. Melissa portal: confirm balance ≥ test budget + margin; record it.
2. Deploy the blueprint backend (`tool/deploy_blueprint.sh`), App Check
   registered and `ENFORCE_APP_CHECK=true`.
3. Set a written test budget: `MELISSA_GLOBAL_DAILY_CREDITS` and
   `MELISSA_OWNER_REQUEST_MAX_CREDITS` ≤ that budget; enable discovery;
   deploy `discoverOwners` only.
4. One verified test account, one new neighborhood; watch
   `melissa_ops.js status`; kill switch ready.
5. Check Firestore (scan + property docs), then repeat the same request →
   0 credits; an overlapping account → 0 or only the missing part.
6. Compare the Melissa portal balance with `estimatedCredits`; stop on any
   difference or error; set `MELISSA_GLOBAL_DAILY_CREDITS` back as approved.

## 7. Remaining cost risks

- Melissa may bill a request that timed out on our side (counted as
  uncharged in our estimate).
- Estimates may drift from Melissa's price list; the portal is authoritative.
- (Fixed 2026-11-24) negative records now last 365 days like the scans, so
  excluded addresses are not re-checked while a scan still lists them.
- Gap-fill and enrichment caches are per user, not shared (both off).

## Limits used up: pending queue

When a daily or monthly limit (or the out-of-credits pause or the kill switch) refuses a verified, genuine request, the area is queued and resumed later under the same limits. See [PENDING_DISCOVERY_QUEUE.md](PENDING_DISCOVERY_QUEUE.md).
