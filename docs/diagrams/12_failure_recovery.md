# 12. API failure and recovery

```mermaid
flowchart TD
  M["Melissa call inside a paid discovery"] --> RG{"Reverse GeoCoder error?"}
  RG -- Yes --> R1["settle whole reservation (undo), lease failed, out_of_credits → set outOfCreditsAt, throw unavailable / resource-exhausted"]
  RG -- No --> SCAN["store scan, charge 2 x addresses returned"]
  SCAN --> PROP["Property lookups"]
  PROP --> PE{"error?"}
  PE -- "network, timeout, rate_limited, unavailable, licence, out_of_credits" --> UC["not charged, not stored — retried by a later discovery"]
  PE -- "other error" --> CH["charged 9, not stored"]
  PE -- "STOP: out_of_credits, license_invalid, license_disabled, product_not_enabled" --> ST["stop loop, out_of_credits → 6 h pause for every paid endpoint"]
  PE -- No --> OK["store named or exclusion immediately"]
  UC & CH & OK & ST --> END["settle unused credits, finishLease, serve from cache"]
  CRASH["Function crash / timeout mid-job"] --> LE["lease expires after 150 s"]
  LE --> NEXT["next request resumes: stored answers reused, only missing lookups made"]
```

```mermaid
flowchart LR
  A1["App offline / callable fails"] --> A2["OwnerArea: transient failure → Overture homes still shown, pull to refresh retries"]
  B1["Budget exhausted / kill switch / unverified"] --> B2["limited answer: stored records + plain message, no automatic retry loop"]
  C1["Firestore unavailable"] --> C2["callable throws internal, app keeps its last list"]
```

**What this shows / where in code.** The `UNCHARGED` and `STOP` sets and the try/catch in `discoverOwners` (`functions/src/owners.js`), plus `OwnerArea._load` and `OwnerDiscoveryService.isKnownReason` / `messageFor` (`lib/core/data/owner_discovery.dart`). Every stored answer is idempotent by its document id (`mel:{MAK}`, `scanIdFor`), so a retry never pays twice for finished work. Being over a limit now returns a `limited` answer instead of an error (local only, 2026-11-24).
