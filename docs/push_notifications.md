# Push notifications (Firebase Cloud Messaging)

## What the app does

| Part | Where |
| --- | --- |
| Permission (alert, sound, badge), asked once when the main app first opens after sign-in | `PushNotificationService.onAppReady` |
| Device token stored at `users/{uid}/devices/{fcmToken}` (`token`, `platform`, `updatedAt`) | `DeviceTokenRepository` |
| Token refresh replaces the old document | `PushNotificationService._onTokenRefresh` |
| Sign-out / account deletion removes the document and deletes the token | `AuthController.addBeforeSignOut` → `PushNotificationService.unregister`; `UserRepository.deleteUserData` |
| Foreground: iOS shows the system banner; Android shows an in-app banner | `FirebasePushMessagingClient.configureForeground`, `_onForeground` |
| Background / terminated: shown by the system (iOS APNs, Android channel `gps_cielo_general`) | `main.dart` background handler (does no work) |
| Tap opens a screen (launch taps wait for sign-in and the main app) | `_onTap`, `PushPayload` |

Notifications never change prayers, visits or any household status.

## Payload

Send a **notification** message (title + body) with this optional `data`:

| Key | Values | Effect |
| --- | --- | --- |
| `type` | `prayerReminder`, `followUpDue`, `milestone`, `scripture`, `churchNews` | Picks the default screen |
| `route` | `/home`, `/neighborhood`, `/prayer-list`, `/follow-up`, `/profile`, `/notifications` | Screen a tap opens. Anything else opens the inbox |
| `householdId` | a household id | Reserved for later; not used for access |

Defaults: `prayerReminder` and `milestone` open the Prayer List, `followUpDue` opens Follow-up, everything else opens Notifications.

## Sending today (Spark plan, no backend)

Firebase Console → **Messaging** → **New campaign** → **Notifications**:

* **Test message:** paste an FCM token. Tokens are in Firestore at `users/{uid}/devices` (the document id).
* **Everyone:** target the iOS and/or Android app.
* Under **Additional options → Custom data**, add `type` / `route` as above.

## Automatic notifications (needs a decision)

Scheduled or event-driven pushes, such as a daily prayer reminder at the user's local time or a follow-up due date, need a trusted server holding service-account credentials. The Flutter app must never hold them. Options:

1. **Cloud Functions** (scheduled + Firestore triggers). Requires the **Blaze** plan, which costs little at this scale but needs approval.
2. **Another server you already run**, using the Firebase Admin SDK and FCM HTTP v1. It reads `users/*/devices`.

Either way, the server should:

* send per user to every token in `users/{uid}/devices`;
* delete a device document when FCM answers `UNREGISTERED` or `INVALID_ARGUMENT` for its token;
* for prayer reminders, use the user's own time zone and daily goal, and skip users who already reached today's goal.

Product decisions still open: which reminders to send, at what time, and whether users can switch each one off in Profile.

## iOS signing

* Release builds sign with `ios/Runner/RunnerRelease.entitlements` (`aps-environment`). App Store export sets it to `production` from the distribution profile.
* Debug keeps `Runner.entitlements` (no push) because the local development profile has no push. To test push in Debug, regenerate that profile with Push Notifications and point Debug at `RunnerRelease.entitlements`.
* The App Store profile must have been created **after** Push Notifications was enabled for the App ID. The Codemagic `ios-testflight` workflow checks this before building, and checks the IPA for `aps-environment = production`.

## Platform setup checklist

### iOS
- [x] `UIBackgroundModes` → `remote-notification` (Info.plist)
- [x] `aps-environment` in `RunnerRelease.entitlements` (Release; App Store export sets production). Debug stays without push on purpose (see iOS signing above); test push with a TestFlight build.
- [x] Foreground banners: `setForegroundNotificationPresentationOptions`
- [x] Waits for the APNs token before asking FCM for a token
- [ ] Apple Developer → Identifiers → `org.gaccchurch.gpsceilo` → **Push Notifications** enabled, and the App Store profile regenerated afterwards (Codemagic checks this)
- [ ] Firebase Console → gps-cielo → Project settings → **Cloud Messaging** → Apple app: upload an **APNs Authentication Key** (.p8, with Key ID and Team ID). Without it no iOS device receives anything.
- Push does not work on the iOS Simulator for FCM; use a real iPhone.

### Android
- [x] `google-services.json` (gps-cielo, `org.gaccchurch.gpsceilo`) and the Google Services Gradle plugin
- [x] `POST_NOTIFICATIONS` permission (Android 13+), asked by `requestPermission`
- [x] Channel `gps_cielo_general` (high importance) created in `MainActivity`, set as the FCM default
- [x] Monochrome status-bar icon `@drawable/ic_stat_notification`, tinted `@color/notification_color`
- [x] Foreground: in-app banner (Android shows nothing on its own while the app is open)

### Both
- [ ] Deploy the Firestore rules (`firebase deploy --only firestore:rules --project gps-cielo`). The rules live before 2026-11-11 have no `users/{uid}/devices` rule, so saving the device token is denied and no device can be targeted.
