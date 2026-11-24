# 5. Overlapping geographic cache reuse

```mermaid
flowchart LR
  subgraph Stored["Stored scans — owner_scans"]
    SA["Scan A: center, coveredMeters, candidates by MAK"]
    SC["Scan C: center, coveredMeters, candidates by MAK"]
  end
  B["New home B overlapping A and C"] --> Q["loadScans: geohash-5 cells around B, radius maxScan+search — boundary-safe"]
  Q --> F["keep scans whose disc can reach B's search disc, drop expired"]
  SA --> F
  SC --> F
  F --> M["merge candidates into Map by id mel:MAK — duplicates counted, kept once"]
  M --> D["sort by haversine distance from B"]
  D --> CR["coveredRadius: largest disc around B inside the union of scan discs, sampled every 10 m, rounded down"]
  D --> W["walk nearest first, getAll owner_properties in chunks of 60"]
  W --> K["skip suites and multi-unit, skip expired = unresolved, skip non-named, dedupe parcelId"]
  K --> N["up to 50 named homes"]
  CR --> CP{"50th named home within covered radius and no closer unresolved?"}
  N --> CP
  CP -- Yes --> COMPLETE["complete — 0 credits"]
  CP -- No --> PART["partial — missing lookups planned, nothing invented"]
```

```mermaid
flowchart TD
  P1["B 1 m from A"] --> R1["same scans, same properties → complete, 0 credits"]
  P2["B across a geohash-5 edge"] --> R2["cellsAround includes neighbour cell → scan still found"]
  P3["B overlaps 2..5 scans"] --> R3["union of discs, each property once"]
  P4["B far from any scan"] --> R4["unknown → cache-only or paid scan if enabled"]
```

**What this shows / where in code.** `cellsAround`, `loadScans`, `coveredRadius` and `serveFromCache` in `functions/src/property_cache.js`. The tests are in `functions/test/blueprint.test.js`: "A/B 1 m apart", "B overlaps two cached scans", "five cached scans" and "geohash boundary". `owner_properties` are shared by every user (`MELISSA_OWNER_SHARED_CACHE=true`), so a property paid for once is reused by every overlapping neighborhood. Coverage is only labelled `complete` when the union of scan discs proves it. A merely full list of 50 is not enough.
