# 10. Household identity and user-specific prayer data

```mermaid
flowchart TD
  subgraph Shared["Shared, server-written, refreshable"]
    OV["Overture home in cells/{geohash} — id from Overture"]
    OP["owner_properties/mel:{MAK} — recorded owner, expiresAt"]
  end
  subgraph Private["Private, per user, never refreshed by Melissa"]
    HS["users/{uid}/household_status/{householdId}: isPrayed, isVisited, isInvited, hasFollowUp, notes, residentName"]
    PL["users/{uid}/prayer_log/{roundId}_{householdId}"]
    PRD["users/{uid}/prayer_rounds/{roundId}.members"]
  end
  OV -->|"same street address, OwnerOverlayArea"| T["Title on screen: residentName → owner name → Unknown Resident, address always shown"]
  OP --> T
  HS --> T
  OV -. "householdId" .-> HS
  OV -. "householdId" .-> PL
  OV -. "householdId" .-> PRD
```

```mermaid
flowchart LR
  RF["Melissa refresh / TTL migration of owner_properties"] --> OP2["only owner_properties fields change, id mel:MAK unchanged"]
  OP2 -. "no write" .-> HS2["household_status untouched"]
  DEL["Account deleted — cleanupDeletedUser"] --> X["users/{uid}/** removed, primary_locations/{uid}, usage counters, u_{uid}_ jobs"]
  DEL -. "kept" .-> OP3["owner_scans / owner_properties shared"]
```

**What this shows / where in code.** Ids are stable keys. Owner records are keyed `mel:{MAK}` (`propertyDoc` in `property_cache.js`), and prayer data is keyed by the household id the app shows. `OwnerOverlayArea` only decorates an Overture home and keeps its id, so prayer history, rounds and follow-ups survive any owner-data change. A user-entered `residentName` is stored separately from the Melissa owner, and an owner is never labelled a verified resident. Deletion runs in `functions/src/cleanup.js` (the per-user job-prefix query was fixed on 2026-11-24; local only).
