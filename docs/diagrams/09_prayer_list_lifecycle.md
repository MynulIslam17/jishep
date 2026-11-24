# 9. Prayer List lifecycle

```mermaid
flowchart TD
  L["Home / Prayer List open"] --> S["HouseholdStore.bindUser — saved home, prayerCycleStartedAt"]
  S --> R["_loadRound: users/{uid}/prayer_rounds/r{cycleStart ms}"]
  R --> FX{"round has fixed members?"}
  FX -- No --> MK["_maybeFixRound: once the neighborhood is settled, save members, center, target"]
  FX -- Yes --> LIST["Prayer List = the round's members — same homes all round"]
  MK --> LIST
  LIST --> PR["togglePray → saveStatus"]
  PR --> W1["users/{uid}/household_status/{householdId}: isPrayed, prayedAt"]
  PR --> W2["users/{uid}/prayer_log/{roundId}_{householdId}"]
  W1 & W2 --> P["daily progress vs dailyPrayerTarget, lifetime = prayer_log count"]
  P --> DONE{"all homes of the round prayed?"}
  DONE -- Yes --> NEW["startNewCycle → UserRepository.startPrayerRound: close old round, open new one, move prayerCycleStartedAt"]
  NEW --> R
  DONE -- No --> LIST
```

```mermaid
flowchart LR
  A["mark prayed / change tab / new round / pull to refresh"] -->|"never"| M["Melissa"]
  A --> C["Firestore reads/writes of the user's own documents only"]
```

**What this shows / where in code.** `lib/core/services/household_store.dart` (`_loadRound`, `_maybeFixRound`, `_homeList`), `lib/features/prayer_list/domain/services/prayer_list_service.dart` (`togglePray`, `startNewCycle`), `HouseholdRepository.saveStatus`, and `UserRepository.startPrayerRound`. Event ids are `{roundId}_{householdId}`, so earlier rounds are never overwritten. A refresh that would cost money happens only in `discoverOwners`, and it is cache-first and OFF in production.
