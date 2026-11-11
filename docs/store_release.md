# Store release checklist

What the app asks the user for, what each platform declares, and what is
still needed in App Store Connect and Google Play Console. Privacy answers are
in `docs/store_privacy.md`; push setup in `docs/push_notifications.md`.

## Runtime permissions (asked inside the app)

| Permission | When it is asked | If denied |
| --- | --- | --- |
| Location (while using the app) | Location setup, "use my current location" | User types an address; a button opens Settings when permanently denied |
| Notifications | Once, when the main app first opens after sign-in | App works; no pushes |
| Photos | Edit Profile → change photo (system photo picker) | Photo unchanged |

The app never asks for background location, camera, contacts, tracking (ATT)
or storage.

## iOS (`ios/Runner/Info.plist`)

- [x] Purpose strings: location (when in use, plus the two "Always" keys), photo library, camera. Keep all of them even though the app uses only when-in-use location and the photo library: App Store Connect rejects uploads (ITMS-90683) when a linked plugin's API has no string.
- [x] Push: `remote-notification` background mode, `aps-environment` in the Release entitlements
- [x] Sign in with Apple entitlement
- [x] `ITSAppUsesNonExemptEncryption = false` (no export-compliance question per build)
- [x] App privacy manifest `PrivacyInfo.xcprivacy` (no tracking, collected data types, UserDefaults reason CA92.1). Plugins and Firebase ship their own.
- [x] iPhone only (`TARGETED_DEVICE_FAMILY = 1`), portrait only. iPad support can be added in a later version; it can't be removed once shipped.
- [x] Home-screen name: **GPS Cielo**

App Store Connect (manual):
- [ ] App name, subtitle, description, keywords, support URL, marketing URL
- [ ] Privacy Policy URL (https://gps-cielo.web.app/privacy, after the hosting deploy)
- [ ] App Privacy questionnaire (`docs/store_privacy.md`)
- [ ] Age rating questionnaire
- [ ] Screenshots: 6.9" iPhone (and 6.5" if asked)
- [ ] **App Review notes with a demo account** (email + password, home location already set) so the reviewer can see households. Without one, review is usually rejected.
- [x] No payments of any kind: donations were removed, and there are no in-app purchases or subscriptions.
- [ ] APNs key uploaded in Firebase (see push doc)

## Android (`android/app/src/main/AndroidManifest.xml`)

Final permissions in the build (checked with `aapt2 dump permissions`):
`INTERNET`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`,
`POST_NOTIFICATIONS`, plus ones added by Firebase / Google sign-in:
`WAKE_LOCK`, `ACCESS_NETWORK_STATE`, `c2dm RECEIVE`, `READ_GSERVICES`,
`USE_BIOMETRIC` / `USE_FINGERPRINT` (Google Credential Manager). No storage,
camera, background location or advertising ID.

- [x] App name **GPS Cielo**, target SDK 36, min SDK 26
- [x] Notification channel and monochrome status-bar icon
- [x] Release signing from `android/key.properties` (falls back to the debug key with a warning when missing)

### Create the upload key (once; keep it safe forever)

```sh
keytool -genkey -v -keystore ~/gps-cielo-upload.jks -storetype PKCS12 \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then create `android/key.properties` (ignored by git):

```
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=/Users/<you>/gps-cielo-upload.jks
```

Build: `flutter build appbundle --release` → `build/app/outputs/bundle/release/app-release.aab`.
Use **Play App Signing** (default) so a lost upload key can be reset.

Google Play Console (manual):
- [ ] Store listing: name, short and full description, icon 512×512, feature graphic 1024×500, phone screenshots
- [ ] App content: Privacy Policy URL, Data safety (`docs/store_privacy.md`), account deletion URL, ads = **No**, target audience (13+), content rating, News app = No
- [ ] App access: demo account credentials for the reviewer
- [ ] New personal developer accounts must run a closed test with at least 12 testers for 14 days before production; organization accounts don't.

## Version numbers

`pubspec.yaml` `version: 1.0.0+1`: raise the part after `+` for every upload
to either store (Codemagic picks the next iOS build number automatically).
