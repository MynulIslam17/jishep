# 4. Cache-first household discovery (`discoverOwners`)

```mermaid
flowchart TD
  R["Callable discoverOwners — request.auth, data {latitude?, longitude?, target}"] --> A{"allowOwnerNames? uid? cacheDays>0?"}
  A -- No --> X1["throw failed-precondition / unauthenticated"]
  A -- Yes --> V["validateOwners — target 1..50, coords optional, US only"]
  V --> H["primaryLocation: primary_locations/{uid}, else pin users/{uid}"]
  H --> T{"client coords farther than 250 m from home?"}
  T -- Yes --> X2["permission-denied location_not_authorized + deniedSecurity++"]
  T -- No --> SV["serveFromCache around the SAVED home"]
  SV --> C{"completeness complete or empty?"}
  C -- Yes --> HIT["return cached records, 0 credits, ownerCacheHits++"]
  C -- No --> LG{"unknown and legacy owner_areas valid?"}
  LG -- Yes --> HIT2["return legacy records, 0 credits"]
  LG -- No --> PM["planMissing: scan needed? lookups needed? estimated credits"]
  PM --> EN{"enabled? AND something missing?"}
  EN -- No --> CO["cache-only answer with missing{} — PRODUCTION TODAY"]
  EN -- Yes --> GT{"verified account? kill switch off?"}
  GT -- No --> LIM["limited: unverified / paid_disabled, records so far"]
  GT -- Yes --> PAID["Paid discovery — see diagram 8 and 7"]
  PAID --> OUT["store every answer, re-serve from cache, return"]
```

**What this shows / where in code.** `discoverOwners()` in `functions/src/owners.js`, using `serveFromCache()` and `planMissing()` in `functions/src/property_cache.js`. Firestore is always read before Melissa. With `MELISSA_OWNER_DISCOVERY_ENABLED=false` (production and local) the flow stops at "cache-only": it returns what is stored, plus exactly what a paid discovery would add. The location and verified-account checks are part of the 2026-11-24 changes, which are local only and not deployed. The app turns the answer into Overture-matched names through `OwnerArea` and `OwnerOverlayArea` (`lib/core/data/owner_discovery.dart`).
