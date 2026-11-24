# 1. Complete application architecture

Status legend: solid = live in production (`gps-para-el-cielo`); dashed / "OFF" = built but switched off; "local only" = 2026-11-24 changes not yet deployed.

```mermaid
flowchart TD
  subgraph App["Flutter app (iOS / Android) — GetX"]
    UI["Screens: Splash, Auth, Location setup, Home, Neighborhood, Prayer List, Follow-up, Profile"]
    Store["HouseholdStore (lib/core/services/household_store.dart)"]
    Repo["HouseholdRepository.nearestArea"]
    Cells["FirestoreCellSource — Overture homes"]
    Overlay["OwnerOverlayArea — owner names matched by street address"]
    OwnerSvc["OwnerDiscoveryService → callable discoverOwners"]
    UI --> Store --> Repo
    Repo --> Cells
    Repo --> Overlay
    Overlay --> Cells
    Overlay --> OwnerSvc
  end

  subgraph Firebase["Firebase project gps-para-el-cielo"]
    Auth["Firebase Auth: email, Google, Apple, phone"]
    FS[("Cloud Firestore")]
    subgraph Fns["Cloud Functions us-central1"]
      DO["discoverOwners — cache first"]
      EH["enrichHousehold"]
      DN["discoverNearby — gap fill"]
      CU["cleanupDeletedUser — auth onDelete"]
    end
    SM["Secret Manager: MELISSA_CREDIT_LICENSE"]
    AC["App Check: Play Integrity / DeviceCheck (new builds), soft gate on paid lookups (local, not deployed)"]
  end

  Melissa["Melissa APIs: Reverse GeoCoder, Property"]

  App -->|"sign in"| Auth
  Cells -->|"read cells/{geohash}"| FS
  Store -->|"read/write users/{uid}/**"| FS
  OwnerSvc -->|"HTTPS callable"| DO
  DO --> FS
  EH --> FS
  DN --> FS
  CU --> FS
  Fns -. "secret" .- SM
  DO -. "paid discovery OFF in prod" .-> Melissa
  DN -. "gap fill OFF" .-> Melissa
  EH -. "global daily budget 0" .-> Melissa
  AC -. "enforceAppCheck=false" .- Fns
```

**What this shows / where in code.** The list of homes comes from Overture building data stored as gzipped geohash cells in Firestore `cells` (`lib/core/data/cell_source.dart`, `HouseholdRepository.nearestArea`). Melissa owner records are an overlay only: `OwnerOverlayArea` (`lib/core/data/owner_discovery.dart`) adds a recorded owner to an Overture home with the same street address. It never adds or replaces homes. All Melissa traffic runs server-side in `functions/src/index.js` (`discoverOwners`, `enrichHousehold`, `discoverNearby`). The Melissa key lives only in Secret Manager. In production every paid path is blocked, because `MELISSA_GLOBAL_DAILY_CREDITS=0` and `MELISSA_OWNER_DISCOVERY_ENABLED=false` (`functions/.env.gps-para-el-cielo`). App Check is not enforced: `ENFORCE_APP_CHECK=false`, and the app ships no App Check provider.
