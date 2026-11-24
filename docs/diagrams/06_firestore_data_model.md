# 6. Firestore data model

```mermaid
erDiagram
  USERS ||--o{ HOUSEHOLD_STATUS : "private prayer/visit/follow-up state"
  USERS ||--o{ PRAYER_LOG : "one event per round per home"
  USERS ||--o{ PRAYER_ROUNDS : "homes of each round"
  USERS ||--o{ NOTIFICATIONS : inbox
  USERS ||--o{ DEVICES : "FCM tokens"
  USERS ||--o{ ENRICHMENT : "server-written address checks"
  USERS ||--o| PRIMARY_LOCATIONS : "server pin, LOCAL ONLY"
  USERS ||--o{ LOCATION_CORRECTIONS : "audit, LOCAL ONLY"
  OWNER_SCANS }o--o{ OWNER_PROPERTIES : "candidates reference mel:MAK"
  HOUSEHOLD_STATUS }o--o| OWNER_PROPERTIES : "same household id mel:MAK, no copy"
  CELLS ||--o{ HOUSEHOLD_STATUS : "Overture ids"

  USERS {
    string fullName
    string address
    number latitude "locked after first set"
    number longitude "locked after first set"
    timestamp locationConfirmedAt "new, optional"
    int locationVersion "new, optional"
    int dailyPrayerTarget
    timestamp prayerCycleStartedAt
  }
  HOUSEHOLD_STATUS {
    bool isPrayed
    bool isVisited
    bool isInvited
    bool hasFollowUp
    string residentName "user-entered, never Melissa"
    string notes
  }
  PRAYER_LOG {
    string householdId
    string roundId
    timestamp prayedAt
  }
  PRAYER_ROUNDS {
    list members
    latlng center
    int target
    timestamp completedAt
  }
  OWNER_SCANS {
    map center
    string geohash5
    number coveredMeters
    bool capped
    list candidates
    timestamp scannedAt
    timestamp expiresAt
  }
  OWNER_PROPERTIES {
    string id "mel:MAK"
    string status "named, not_found, mismatch, non_residential, multi_family, no_owner"
    map owner "name, secondName, isCompany, isTrust"
    string parcelId
    string geohash
    timestamp checkedAt
    timestamp expiresAt
  }
  PRIMARY_LOCATIONS {
    number latitude
    number longitude
    int version
    string source
  }
  LOCATION_CORRECTIONS {
    string uid
    string operator
    string reason
    map fromLocation
    map toLocation
  }
  CELLS {
    string id "geohash cell"
    bytes gz "Overture homes"
  }
```

| Path | Client access (firestore.rules) | Writer |
|---|---|---|
| `users/{uid}` | owner read/write; location fields locked once set *(local only)* | app |
| `users/{uid}/household_status`, `prayer_log`, `prayer_rounds` | owner only, verified accounts write | app |
| `users/{uid}/enrichment`, `gap_areas` | owner read/delete | functions |
| `cells/{id}`, `households/{id}` | signed-in read | admin seed tools |
| `owner_scans`, `owner_properties`, `owner_areas`, `discovery_jobs`, `melissa_usage/**` | none | functions |
| `primary_locations`, `location_corrections` *(local only)* | none | functions / operator tools |

**What this shows / where in code.** `firestore.rules`, `functions/src/property_cache.js` (`scanDoc`, `propertyDoc`), `functions/src/location.js`, and `lib/core/constants/firestore_paths.dart`. Shared property data and private prayer data are separate layers. Prayer documents reference a household id only and never copy owner data.
