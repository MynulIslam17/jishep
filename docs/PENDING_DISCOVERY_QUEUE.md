# Pending owner discovery: when the credit limits run out

Status **2026-11-24**: implemented and tested locally. **Not deployed.**
Paid discovery is **off** in production. Code: `functions/src/queue.js`,
`functions/src/owners.js`, `functions/src/index.js` (`processDiscoveryQueue`),
`lib/core/data/owner_discovery.dart`. Tests: `functions/test/queue.test.js`
(25 tests), `test/owner_discovery_test.dart` (queued cases).

## 1. Review: what happens when a limit is used up

| Limit hit | Before the queue | Now |
|---|---|---|
| App daily (`MELISSA_OWNER_DAILY_CREDITS` / global daily) | stored homes, or "paused" note; the area waited until the user opened the app on a later day | same answer **and the area is queued**; it resumes by itself |
| App monthly (`MELISSA_OWNER_MONTHLY_CREDITS`) | stored homes, generic note | same, queued |
| Melissa out of credits (6 h pause) | stored homes | same, queued |
| Kill switch (`paidDisabled`) | stored homes | same, queued; nothing runs until the switch is cleared |
| Per user per day (5) | refused for that user | unchanged (anti-abuse; not queued) |
| Unverified account / no App Check token | stored homes, nothing paid | unchanged: **never queued** |

In every case:
- **Sign-up still works**, the primary location is saved (client write
  allowed by the rules for the first save), and the app opens normally.
- **Cached household records are served**, with 0 credits.
- **Prayer data is not touched.**

Nothing in the queue writes to `users/*`.

## 2. How the queue works

```
discoverOwners (budget refusal, verified + App Check + saved home)
  → discovery_queue/{scope_geohash6}   one job per area, server-only
        requesters {uid: {appCheck, at}}  (max 20)

processDiscoveryQueue (every 30 min; returns at once while paid is off)
  for up to 5 due jobs, oldest first:
    claim (transaction; one run per job)
    for each requester:
      App Check flag recorded? account still exists, enabled, verified?
      → discoverOwners as that user (queue off):
           cache first (filled meanwhile → done, 0 credits)
           home still in this area? (else dropped)
           kill switch, pause, per-request / user / daily / monthly /
           global reservation (same transaction as live requests)
    budget refused → job waits, the run stops (no attempt counted)
    found          → done; requesters cleared
    no valid requester left → cancelled
    errors → retried with back-off, failed after 5 attempts
```

## 3. Abuse limits

| Limit | Default | Setting |
|---|---|---|
| Who can queue | verified account, valid App Check token, server-pinned home | same gates as paid discovery |
| Jobs per area | 1 (deduplicated, also under concurrency) | — |
| New jobs per UTC day | 50 | `MELISSA_OWNER_QUEUE_DAILY_NEW` |
| Open jobs at once | 200 | `MELISSA_OWNER_QUEUE_MAX_OPEN` |
| Requesters per job | 20 | code (`queueMaxRequesters`) |
| Jobs per run | 5 (every 30 min) | `MELISSA_OWNER_QUEUE_JOBS_PER_RUN` |
| Job lifetime | 30 days, then expired | code (`queueMaxAgeDays`) |
| Credits | **no budget of its own**: every job reserves through the same atomic limits as live requests | — |
| Queue off switch | `MELISSA_OWNER_QUEUE_ENABLED=false` | — |

Homes are locked, so one account can be in only one area's job.
Repeated sign-ups in one area add nothing. Sign-ups spread across new areas
hit the daily and open caps. Processing can never go past the credit
limits.

## 4. App

| Server answer | App shows |
|---|---|
| queued, nothing stored | "We're gathering the homes in your neighborhood. They'll appear here automatically when ready." |
| queued, some stored | the stored homes, plus "More homes in your neighborhood will be added automatically." |

The app shows no time and no internal words. The homes appear on the next
load (open or refresh) after the job is done. A prayer round is never fixed
on an empty list, which is unchanged behavior.

## 5. Data

- The job holds the area key, the requesters' uids and timestamps only: no
  coordinates, names or addresses.
- The requesters are cleared when the job ends.
- Deleting an account removes the uid (`cleanup.js`).
- Rules: `discovery_queue` allows no client read or write (`rules.test.js`).
- Answers are stored by `discoverOwners` with the 365-day policy (tested).

## 6. Deployment (needs the owner's approval; not done)

1. Backend deploy (`tool/deploy_blueprint.sh --approve=gps-para-el-cielo`).
   It adds `processDiscoveryQueue`, the `discovery_queue` rule and its index.
   The Cloud Scheduler API (`cloudscheduler.googleapis.com`) must be enabled
   on gps-para-el-cielo; it is **not** enabled today. Paid stays off, so
   the processor does nothing.
2. Activation (`tool/activate_paid.sh`) now deploys `discoverOwners` and
   `processDiscoveryQueue` with the approved limits. The preflight checks
   that the processor is ACTIVE and the Scheduler API is enabled.
