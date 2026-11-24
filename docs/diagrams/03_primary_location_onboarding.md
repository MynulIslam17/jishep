# 3. Primary location onboarding

```mermaid
flowchart TD
  S["LocationSetupScreen step 1: search address or use GPS"] --> P["Step 2: confirm pin on the map"]
  P --> PV["Preview nearby homes: nearestArea with preview:true — Overture cells only, NEVER Melissa"]
  P -->|"drag pin → adjustPin → debounced preview"| PV
  PV --> G["Step 3: daily prayer goal, intention"]
  G --> N["_FixedLocationNote: choose carefully, later changes via support"]
  N --> C["confirmLocation — guarded by isSubmitting"]
  C --> W["AuthService.updateLocation: address, latitude, longitude, locationConfirmedAt=serverTimestamp, locationVersion=1"]
  W -->|"permission-denied on rules older than 2026-11-24"| W2["retry without the confirmation fields"]
  W --> M["Get.offAllNamed mainNav"]
  W2 --> M
```

```mermaid
stateDiagram-v2
  [*] --> NoLocation: new account
  NoLocation --> Locked: first client write of latitude/longitude
  Locked --> Pinned: first discoverOwners call creates primary_locations/{uid}
  Locked --> Locked: client edit of address/latitude/longitude refused by rules
  Pinned --> Pinned: users/{uid} deleted and re-created elsewhere — server keeps the pin
  Pinned --> Corrected: support runs tool/location_admin.js correct
  Corrected --> Pinned: version+1, audit in location_corrections
  note right of Locked
    Rules + server pin: LOCAL ONLY (2026-11-24),
    not deployed to production yet
  end note
```

**What this shows / where in code.** `lib/features/auth/presentation/controllers/location_setup_controller.dart` (`_loadPreview` passes `preview: true`, `confirmLocation`). `HouseholdRepository.nearestArea(preview:)` skips both the gap-fill and the owner overlay, so typing, dragging the pin or map movement can never cost credits. The lock lives in `firestore.rules` (`locationChangeAllowed`, `locationConfirmationValid`). The server pin is `primaryLocation()` in `functions/src/owners.js`. Corrections go through `correctPrimaryLocation()` in `functions/src/location.js`, run only from `functions/tool/location_admin.js`. The app has no edit control: the former Profile address sheet, the "Change home address" buttons and "Set as my home" were all removed.
