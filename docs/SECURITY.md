# Security model — GPS PARA EL CIELO

Part of the master blueprint (`docs/GPS_PARA_EL_CIELO_MASTER_BLUEPRINT.md` §16).
Describes what is **implemented in the repository** as of 2026-11-24 and
what is **deployed**. Everything added on 2026-11-24 is **local only** (not
deployed to `gps-para-el-cielo`); see `docs/PRODUCTION_DEPLOYMENT.md` › Release log.

## 1. Summary

| Control | Implemented | Deployed (prod) | Where |
|---|---|---|---|
| Firebase Auth on every callable | ✅ | ✅ | `functions/src/*.js` (`sign_in_required`) |
| Verified account for user activity writes | ✅ | ✅ | `firestore.rules` `verified()` |
| Verified account for **paid** discovery | ✅ | ❌ local only | `owners.js` `isVerifiedToken`, `MELISSA_OWNER_REQUIRE_VERIFIED=true` |
| Server-authoritative primary location | ✅ | ❌ local only | `owners.js` `primaryLocation()`, `primary_locations/{uid}` |
| Rules lock on the client's location fields | ✅ | ❌ local only | `firestore.rules` `locationChangeAllowed()` |
| Audited admin location correction | ✅ | ❌ local only | `functions/src/location.js`, `functions/tool/location_admin.js` |
| Kill switch for every paid endpoint | ✅ | ❌ local only | `budget.js` `paidDisabled`, `tool/melissa_ops.js kill` |
| App-wide / monthly / per-user / per-request budgets | ✅ | ✅ (budget 0) | `budget.js`, `owners.js` `reserveOwners` |
| Server-only shared cache, locks, counters | ✅ | ✅ | `firestore.rules` (`if false`) |
| Melissa key only in Secret Manager | ✅ | ✅ | `MELISSA_CREDIT_LICENSE` |
| Emulator replay-only / tests no network | ✅ | n/a | `guard.js`, `test/no_network.js` |
| **App Check** | ✅ client + soft gate (local) | ❌ not deployed / not enforced | console registration pending (§4, [APP_CHECK.md](APP_CHECK.md)) |

## 2. Authentication and verification

- Supported sign-ins: email/password, Google, Sign in with Apple, phone.
- **Rules** (`firestore.rules` `verified()`): `email_verified == true`, or
  provider in `google.com | apple.com | phone`. Required for writing
  `household_status`, `prayer_log`, `prayer_rounds`, `support_messages`.
  An unverified password account can still finish its profile and location.
- **Server** (`owners.js` `isVerifiedToken(request.auth.token)`): the same
  definition. An unverified caller gets cached data only; a paid discovery
  answers `limited: 'unverified'` and counts `deniedSecurity` — no lease,
  no reservation, no Melissa call.
- Every callable refuses a missing `request.auth` (`unauthenticated /
  sign_in_required`) before reading anything.

## 3. Primary location: chosen once, enforced on the server

Policy (blueprint §2.1): the user picks a primary location during signup;
ordinary users cannot change it afterwards.

Three layers, none of which trusts the UI:

1. **App** — no screen offers a change (Profile shows it read-only with
   "Contact support"; `test/fixed_location_test.dart` fails the build if a
   change control or `HomeAddressService` comes back).
2. **Firestore rules** — once `users/{uid}` has `latitude`/`longitude`,
   any client change of `address`, `latitude`, `longitude`,
   `locationConfirmedAt` or `locationVersion` is refused
   (`locationChangeAllowed()`). The first save may stamp
   `locationConfirmedAt`, which must equal `request.time`. Existing users
   with saved coordinates are locked with **no data migration**.
3. **Server** — `discoverOwners` never searches a client-chosen point.
   `primaryLocation()` pins the home in **`primary_locations/{uid}`**
   (server-only) the first time it sees it, copied from `users/{uid}`.
   Deleting and re-creating the profile does not move the pin. A request
   whose coordinates are more than **250 m** (`MELISSA_OWNER_LOCATION_TOLERANCE_M`)
   from the pin is refused with `permission-denied / location_not_authorized`
   (counted as `deniedSecurity`). No saved home → `no_primary_location`;
   a home outside the US → `outside_us`.

The Neighborhood "look around another place" browse was removed on
2026-11-24 (client approved signup-only location). The only place the app
ever builds a non-home area is the setup preview (`preview: true`, Overture
only, never `discoverOwners`).

### Admin correction (moves, wrong address)

`functions/src/location.js` `correctPrimaryLocation`, run **only** from the
operator tool `functions/tool/location_admin.js correct` with the
operator's Application Default Credentials. There is **no callable
function**, so no client can reach it.

- explicit `--operator` and `--reason` (≥ 5 chars) required;
- at most **2 corrections per user per 365 days** (`rate_limited`);
- one transaction updates `users/{uid}` + `primary_locations/{uid}`
  (`version+1`, `source: admin_correction`) and creates an immutable
  `location_corrections/{id}` audit record (who, when, from, to, reason);
- prayer status, log, rounds and follow-ups are not touched;
- moving a home buys nothing: the next request is cache-first and every
  paid path keeps its budgets.

## 4. App Check (2026-11-24, local — console steps pending)

Implemented, **not deployed, not enforced**. Full details and the console
steps only the owner can do: [APP_CHECK.md](APP_CHECK.md).

- App: `firebase_app_check` 0.4.8, `AppCheckBootstrap` (Play Integrity /
  DeviceCheck in release, debug provider in debug; never blocks startup).
- Functions, soft gate `MELISSA_REQUIRE_APP_CHECK=true`: without a valid
  token stored data is served but no paid Melissa call can start
  (`limited: app_check` / `app_check_required`, before any reservation).
- Hard gate `ENFORCE_APP_CHECK` and Firestore enforcement stay **off** until
  builds without App Check are retired ([COMPATIBILITY_AUDIT.md](COMPATIBILITY_AUDIT.md)).
- Still open: console registration (DeviceCheck key, Play Integrity +
  SHA-256 fingerprints, debug tokens), a released App Check build, and the
  deploy.

Until then, a scripted client with a valid verified account can call the
callables. Mitigations in place: auth, verified-account gate, saved-home
pin, per-user / app-wide / monthly / per-request budgets, kill switch, and
production budget 0. **Paid discovery must not be enabled before App
Check is enforced** (`docs/PRODUCTION_DEPLOYMENT.md` §7).

## 5. Data access boundaries

| Data | Client | Server |
|---|---|---|
| `users/{uid}` profile | owner read/write (validated fields, location lock) | read |
| `users/{uid}/household_status`, `prayer_log`, `prayer_rounds`, `notifications`, `devices` | owner only | cleanup on delete |
| `users/{uid}/enrichment`, `gap_areas` | owner read/delete | write |
| `owner_scans`, `owner_properties`, `owner_areas` (root and per user) | **none** | read/write |
| `discovery_jobs`, `melissa_usage/**` | **none** | read/write |
| `primary_locations`, `location_corrections` | **none** | read/write |
| `households`, `cells` | signed-in read | admin seed only |
| `support_messages` | create own, read/delete own | console |

Shared property facts (owner names) reach the app only through
`discoverOwners`, never as raw documents. Prayer activity is private per
user and never shared. Account deletion (`cleanupDeletedUser`) removes
`users/{uid}` recursively, `primary_locations/{uid}`, the user's usage
counters and `discovery_jobs/u_{uid}_*` (the job-prefix query was fixed on
2026-11-24 — it previously matched nothing); shared properties stay.

## 6. Secrets

- Melissa credit key: Secret Manager `MELISSA_CREDIT_LICENSE` (version 1,
  automatic replication) on `gps-para-el-cielo`; the runtime service
  account has `secretAccessor` on that secret only.
- Local copy: `~/.config/gps-cielo/melissa.env` (mode 600, outside the
  repo). Never printed; `tool/melissa/probe.js` scrubs output; the recorder
  strips the key from saved responses.
- The deploy upload excludes `.melissa-recordings`, `.secret.local`,
  `.env.local`, `test/`, `tool/` (`firebase.json` ignore list; guarded by
  `zero_budget.test.js` "the deploy package can never contain…").
- Rotation: `docs/INCIDENT_RESPONSE.md` › Leaked key.

## 7. Spending guard and logging

- `guard.js`: in the Functions emulator every Melissa request is replayed
  from `functions/.melissa-recordings` or refused **without network**,
  unless `MELISSA_EMULATOR_LIVE=true` (set nowhere). Tests run with
  `test/no_network.js`: any non-local host throws.
- Logs carry counts and outcome codes only: no uid, address, coordinates,
  owner name or key (`log({event, outcome, ...counts})`).
- `melissa_usage` counters are aggregate; the usage report
  (`tool/melissa_ops.js report`) prints no personal data.

## 8. Account farming and abuse — defences and honest limits

| Attack | Defence | Limit |
|---|---|---|
| Script calls with arbitrary coordinates | server uses the pinned home; >250 m → refused | — |
| Change location via profile edit | rules lock | — |
| Delete/re-create profile elsewhere | `primary_locations` pin survives | account **deletion** frees the uid; a new account is a new uid |
| Many new accounts, each a new area | verified account required; per-user daily limit; app-wide daily + monthly caps; per-request ≤ 920 | without App Check, a farm of verified (e.g. Google) accounts can consume the app-wide cap; the cap bounds the loss, it does not prevent it |
| Repeat requests for the same area | cache-first, lease (`discovery_jobs`), negative cache | — |
| Old app versions | same server checks; old setup writes still accepted once | old app's "My address" edit now fails (intended) once new rules are live |
| Leaked key | Secret Manager only; kill switch; rotate | Melissa bills the key holder until rotated |

## 9. Threat table

| Threat | Likelihood | Impact | Control | Residual |
|---|---|---|---|---|
| Credit drain via callable abuse | medium (App Check not yet live) | high | budgets, verified gate, pin, kill switch, budget 0 in prod | bounded by caps; enforce App Check before paid |
| Owner names scraped for arbitrary places | low | medium | server-chosen point only; rules deny raw reads | one neighborhood per account |
| Cross-user prayer data read | low | high | owner-only rules (tested) | — |
| Forged location after signup | low | medium | rules lock + server pin | — |
| Key exposure | low | high | Secret Manager, scrubbed logs, upload ignore | rotate runbook |
| Operator error (wrong project) | medium | high | tools refuse `cielo-63925`; prod writes need `--approve=<project>` | human review |
| Mass correction abuse by insider | low | low | 2/yr limit, audit trail | — |
