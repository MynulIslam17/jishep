# 11. App Check and backend authorization

```mermaid
flowchart TD
  APP["App build with App Check: AppCheckBootstrap — Android Play Integrity, iOS DeviceCheck, debug provider in debug builds"] --> REQ
  OLD["Builds without App Check (1.0.0 in the stores): no token"] --> REQ
  REQ["Callable request: discoverOwners / enrichHousehold / discoverNearby"] --> AC{"ENFORCE_APP_CHECK (hard)?"}
  AC -- "true: only after old versions are retired" --> HARD{"valid token?"}
  HARD -- No --> E0["unauthenticated — rejected by the Functions SDK"]
  HARD -- Yes --> AU
  AC -- "false (now): request.app set only if the token is valid" --> AU
  AU{"request.auth present?"} -- No --> E1["unauthenticated sign_in_required"]
  AU -- Yes --> LOC["primaryLocation: server pin, not client coordinates"]
  LOC --> FORGE{"client coords > 250 m from pin?"}
  FORGE -- Yes --> E2["permission-denied location_not_authorized"]
  FORGE -- No --> CACHE["cache-first answer (served with or without App Check)"]
  CACHE --> PAY{"paid work needed?"}
  PAY -- Yes --> VER{"isVerifiedToken: email_verified or google/apple/phone"}
  VER -- No --> E3["limited unverified"]
  VER -- Yes --> APPV{"MELISSA_REQUIRE_APP_CHECK and no valid token?"}
  APPV -- Yes --> E4["limited app_check (enrich / gap fill: app_check_required)"]
  APPV -- No --> BUD["kill switch + budgets in one transaction — diagram 7"]
```

```mermaid
flowchart LR
  C["Client SDK"] -->|"users/{uid}/** own docs only"| R["firestore.rules"]
  C -->|"cells, households read"| R
  C -. "denied" .-> S["owner_*, discovery_jobs, melissa_usage, primary_locations, location_corrections"]
  F["Cloud Functions Admin SDK"] --> S
  O["Operator tools with ADC + --approve"] --> S
```

**What this shows / where in code.** Client: `lib/core/services/app_check_bootstrap.dart`, activated in `lib/main.dart` right after `Firebase.initializeApp` (activation errors never block startup). Server: `functions/src/index.js` (`appVerified(request)` → `isAppCheckVerified(request.app)` in `functions/src/owners.js`; soft gate `MELISSA_REQUIRE_APP_CHECK=true`; hard gate `enforceAppCheck: ENFORCE_APP_CHECK`, still `false` so builds without App Check keep working on stored data), `functions/src/enrich.js` / `discover.js` (`app_check_required` before any reservation), and `firestore.rules`. Firestore App Check enforcement stays off until old versions are retired. Status: implemented and tested locally (`functions/test/resilience.test.js`), **not deployed**; console steps in [../APP_CHECK.md](../APP_CHECK.md).
