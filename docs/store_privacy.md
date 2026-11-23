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
| Account deletion URL (Play → Data safety) | https://gps-cielo.web.app/delete-account |
| Support URL (App Store Connect) | https://gps-cielo.web.app/support |
| Marketing URL (optional) | https://gps-cielo.web.app/ |

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

## Values still to confirm with the client

`lib/features/legal/legal_info.dart` holds every organization fact used in
the app, the documents and the website (https://gps-cielo.web.app).

Removed until the client provides them (nothing invented is published):
- A mailing address. The documents give the email only.
- A governing-law state and court venue. The Terms have no such clause.

Confirm:
- Exact legal name: "Global Alliance of Christian Churches, Inc." (from the
  gaccchurch.org header).
- `contactEmail` office@gaccchurch.org is monitored. The website promises
  that people who can't open the app can email it to have their account
  deleted (done by hand in the Firebase console: Authentication user plus
  `users/{uid}` and its subcollections and their `support_messages`).
- The app is free (website and Terms say so; set the price in App Store
  Connect to match).
- Minimum age 13 in the documents versus the 4+ App Store age rating.
- The liability cap of US$100 and other standard clauses in the Terms (have
  counsel review).
- Household listings: the documents say they are added by the organization
  and users can't change them (true in the code: Firestore rules deny client
  writes). Say where the listings come from if the client wants that stated.
