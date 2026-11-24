# Firebase App Check — iOS and Android

Status **2026-11-24**: implemented and tested locally, **not deployed, not
enforced**. Part of the [master blueprint](GPS_PARA_EL_CIELO_MASTER_BLUEPRINT.md);
diagram [11](diagrams/11_app_check_authorization.md).

## 1. What it does

App Check proves a request comes from the genuine app on a real device. It
stops a script that copied the public Firebase config from spending Melissa
credits with throw-away accounts.

| Platform | Release provider | Debug builds |
|---|---|---|
| Android | **Play Integrity** | debug provider |
| iOS | **DeviceCheck** | debug provider |

Why DeviceCheck and not App Attest on iOS: DeviceCheck needs no
entitlement and no provisioning-profile change, so the existing Codemagic
signing (`gps_cielo_appstore_push`, certificate `gps_cielo_distribution`)
works unchanged. App Attest is stronger. It can be switched on later (§5).

## 2. Implementation

| Part | Where | Behaviour |
|---|---|---|
| Client package | `pubspec.yaml` `firebase_app_check: ^0.4.8` | only additions in `pubspec.lock`; iOS via Swift Package Manager (`Package.resolved` gains the recaptcha SDK the plugin depends on) |
| Client activation | `lib/core/services/app_check_bootstrap.dart`, called in `lib/main.dart` `bootstrap()` right after `Firebase.initializeApp` | Play Integrity / DeviceCheck in release, debug provider in debug; token auto-refresh; **errors never block startup** |
| Debug token | `--dart-define=APP_CHECK_DEBUG_TOKEN=<token>` (optional) | otherwise the native SDK prints a token in the log on first run |
| Soft server gate | `functions/src/index.js` `MELISSA_REQUIRE_APP_CHECK` (default **true**) → `appVerified` (`isAppCheckVerified(request.app)`) | no valid token → stored data still served; paid Melissa refused: `discoverOwners` answers `limited: 'app_check'`, `enrichHousehold` / `discoverNearby` throw `failed-precondition / app_check_required` **before** any lease or credit reservation |
| Hard server gate | `ENFORCE_APP_CHECK` in `functions/.env.gps-para-el-cielo` | stays **false** until builds without App Check are retired (§4) |
| Measurement | log `{event:"app_check", fn:"discoverOwners", verified}` per call | Logs Explorer → share of traffic with a token |
| Client message | `OwnerDiscoveryService.messageFor('app_check')` | "More homes for this area will be added soon." (no technical words) |

Tests: `functions/test/resilience.test.js` (gate on all three paid
endpoints, cache still served, old app gets its stored neighborhood),
`test/app_check_bootstrap_test.dart` (providers per build, failure never
blocks), `test/owner_discovery_test.dart` (message). Both native builds
compile with the plugin (`flutter build apk --debug`,
`flutter build ios --simulator --debug`, 2026-11-24).

## 3. Actions only you can do (console)

Nothing here costs money or touches Melissa. Order matters: register the
apps **before** shipping the build, or every release user will lack a
token and be held to stored data.

### Apple Developer (team T83PP9TMXS)

1. Certificates, Identifiers & Profiles › **Keys** › **+** › name
   "GPS Cielo DeviceCheck" › tick **DeviceCheck** › Continue › Register.
2. **Download the .p8 once** (Apple never shows it again) and note the
   **Key ID**. Keep the file out of git.
3. No App ID capability, no new profile and no Codemagic change for
   DeviceCheck.

### Firebase Console (project **gps-para-el-cielo**)

4. App Check › Apps › iOS app `org.gaccchurch.gpsceilo` › **DeviceCheck** ›
   upload the .p8, Key ID, Team ID `T83PP9TMXS` › Save.
5. Project settings › Your apps › Android `org.gaccchurch.gpsceilo` › **Add
   fingerprint** for both of these (SHA-256):
   - the **app signing key** from Play Console › Test and release › App
     integrity › App signing (the key Google re-signs with);
   - the **upload key**: `keytool -list -v -keystore <upload.jks> -alias <alias>`
     (needed for builds you install yourself).
6. App Check › Apps › Android app › **Play Integrity** › Save (accept the
   terms; Firebase enables the Play Integrity API in the Cloud project).
7. App Check › Apps › ⋮ › **Manage debug tokens**: add one token per
   developer simulator/emulator (copy it from the debug log).
8. App Check › **APIs**: leave **Cloud Firestore, Authentication and
   Storage unenforced** (Firestore enforcement would lock out every
   installed 1.0.0 user, see the compatibility audit).

### Google Play Console

9. Test and release › App integrity › **Play Integrity API** › **Link a
   Cloud project** › `gps-para-el-cielo`.
10. Builds you install yourself (not from Play) can fail the integrity
    verdict. Use internal testing or a debug build with a debug token.

### Codemagic

11. iOS: **no change** (DeviceCheck needs no entitlement). The existing
    `ios-testflight` workflow and profile `gps_cielo_appstore_push` work
    as before.
12. Android: no workflow signs releases there today (`docs/store_release.md`).
    If one is added, register its signing key's SHA-256 as in step 5.

## 4. Enforcement plan

| Stage | Setting | Effect | When |
|---|---|---|---|
| 0 (production now) | backend without the gate | — | — |
| 1 soft | deploy with `MELISSA_REQUIRE_APP_CHECK=true`, `ENFORCE_APP_CHECK=false` | old builds: cached data only; new builds: everything | with the blueprint deploy (needs your approval) |
| 2 measure | Logs Explorer `jsonPayload.event="app_check"` | `verified:true` share | after the App Check build is live |
| 3 hard (functions) | `ENFORCE_APP_CHECK=true` + deploy | calls without a token rejected | when ≥ 99 % verified for 2 weeks and the old builds are gone |
| 4 Firestore | Console › App Check › APIs › Cloud Firestore › Enforce | every Firestore read/write needs a token | only after old builds are unsupported (force-update) |

## 5. Optional later: App Attest on iOS

Change the provider to `AppleAppAttestWithDeviceCheckFallbackProvider()`
in `app_check_bootstrap.dart`, then:
- App ID `org.gaccchurch.gpsceilo` › enable **App Attest**;
- regenerate the App Store profile and upload it to Codemagic under the
  same reference name (`gps_cielo_appstore_push`), or update `codemagic.yaml`;
- add `com.apple.developer.devicecheck.appattest-environment` =
  `production` to `ios/Runner/RunnerRelease.entitlements`;
- Firebase › App Check › iOS › App Attest › Save.
