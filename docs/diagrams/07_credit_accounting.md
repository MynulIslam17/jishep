# 7. Melissa credit accounting

```mermaid
flowchart TD
  P["Paid discovery wanted — plan from planMissing"] --> E["estimate: scan 100 x 2 = 200 if needed + lookups x 9, lookups ≤ min maxLookups 80, perRequestMax"]
  E --> TX["reserveOwners — ONE Firestore transaction"]
  TX --> C0{"credits > 0 and ≤ perRequestMaxCredits 920?"}
  C0 -- No --> L1["limited: request_budget"]
  C0 -- Yes --> C1{"melissa_usage/state.paidDisabled? — kill switch, LOCAL ONLY"}
  C1 -- Yes --> L2["limited: paid_disabled"]
  C1 -- No --> C2{"outOfCreditsAt within 6 h?"}
  C2 -- Yes --> L3["limited: out_of_credits"]
  C2 -- No --> C3{"user discoveries today ≥ perUserDaily 5?"}
  C3 -- Yes --> L4["limited: user_daily_limit"]
  C3 -- No --> C4{"owner credits today + est > 2000 OR all endpoints today + est > GLOBAL_DAILY — 0 in prod"}
  C4 -- Yes --> L5["limited: app_daily_limit — EVERY request in prod today"]
  C4 -- No --> C5{"month + est > 20000?"}
  C5 -- Yes --> L6["limited: app_monthly_limit"]
  C5 -- No --> RES["increment day.ownerCredits, day.ownerDiscoveries, month.ownerCredits, day/users/uid"]
  RES --> CALL["Melissa calls: Reverse = 2 x addresses returned, Property = 9 each, except uncharged errors"]
  CALL --> SET["settleOwners: give back reserved − spent, undo the discovery count if nothing was spent"]
  SET --> CNT["countUsage: estimatedCredits, melissaRequests, successful/failedDiscoveries"]
```

| Endpoint | Counter field in `melissa_usage/{day}` | Own limit |
|---|---|---|
| `discoverOwners` | `ownerCredits`, `ownerDiscoveries` (+ `month-YYYY-MM.ownerCredits`) | per request 920, per user 5/day, 2000/day, 20000/month |
| `enrichHousehold` | `credits`, `lookups` | 20 lookups/user/day |
| `discoverNearby` | `gapCredits`, `gapFills` | 3/user/day, 300/day (OFF) |
| all three | `spentToday()` in `budget.js` | `MELISSA_GLOBAL_DAILY_CREDITS` (0 in prod = nothing allowed) |

**What this shows / where in code.** `reserveOwners` and `settleOwners` (`functions/src/owners.js`), `overGlobalLimit`, `spentToday` and `paidDisabled` (`functions/src/budget.js`), and `reserve`/`reserveGap` in `enrich.js`/`discover.js`. All figures are the functions' estimates. Melissa's portal balance is the authority; the last recorded balance is 250 credits, which is less than one new 50-home area costs (~700–920). With a global budget of 0, every paid branch in production ends at `app_daily_limit` before Melissa is contacted.
