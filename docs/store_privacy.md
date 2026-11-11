# Store privacy answers

Answers for the App Store Connect **App Privacy** form and the Google Play
**Data safety** form. They match the Privacy Policy in
`lib/features/legal/legal_content.dart`. If the app starts collecting
something new (analytics, crash reporting, ads), update both.

## URLs to enter

| Field | Value |
| --- | --- |
| Privacy Policy URL (App Store Connect → App Information; Play → App content) | https://gps-cielo.web.app/privacy |
| Terms of Use / EULA (App Store Connect → App Information → License Agreement, or the description) | https://gps-cielo.web.app/terms |
| Account deletion URL (Play → Data safety) | https://gps-cielo.web.app/privacy (section 9 explains in-app deletion; users can also email support) |

The pages go live after `firebase deploy --only hosting --project gps-cielo`.
After changing the legal text, run `dart run tool/build_legal_pages.dart`
first (a test fails if `legal_site/` is out of date).

## Apple: App Privacy

Phone sign-in is off (`AppConfig.phoneAuthEnabled`), so phone numbers are
not listed. Add them back here if it is turned on.

- **Tracking:** No. No data is used to track users across other companies' apps or websites.
- **Data linked to the user** (all used for **App Functionality**; none for advertising or analytics):

| Category | Type | Why |
| --- | --- | --- |
| Contact Info | Name | Profile |
| Contact Info | Email Address | Sign-in, support replies |
| Contact Info | Physical Address | Home address |
| Location | Precise Location | Home location, nearby households (foreground only) |
| User Content | Photos | Profile photo |
| User Content | Customer Support | Contact Support messages |
| User Content | Other User Content | Notes, prayer, visit and follow-up records |
| Identifiers | User ID | Firebase account ID |
| Identifiers | Device ID | Push notification token |

## Google Play: Data safety

- Data collected: **Yes**. Data shared with third parties: **No** (service providers acting for us don't count as sharing).
- Encrypted in transit: **Yes**. Users can request deletion: **Yes** (in-app: Profile → Delete account).
- Collected types, all **required for app functionality**, **not optional** unless noted:
  - Personal info: Name; Email address; Address; Other info (church affiliation, optional)
  - Location: Precise location (optional; the user can type an address instead)
  - Photos and videos: Photos (optional, profile photo)
  - Messages: Other in-app messages (support messages, optional)
  - App activity: Other user-generated content (notes and outreach records)
  - Device or other IDs: Device or other IDs (push token)

## Values still to confirm

`lib/features/legal/legal_info.dart` holds every organization fact used in
the documents. These are **placeholders** because gaccchurch.org doesn't list
them:

- `mailingAddress`
- `governingState` and `venueCounty`

Also confirm:

- `contactEmail`: support@gpscielochurch.org is the address the app already shows. The church site shows info@gacchurch.org instead.
- That household listings really come from "publicly available sources and participating churches" (Privacy Policy section 6, Terms section 6).
