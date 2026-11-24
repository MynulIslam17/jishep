# UI / UX design system

Status 2026-11-24. Scope chosen by the project owner on 2026-11-24:
**targeted** — keep the App Store–approved visual design (1.0.0), codify it
here, and change only what the fixed-location model requires. A full visual
redesign was explicitly not chosen. Part of the
[master blueprint](GPS_PARA_EL_CIELO_MASTER_BLUEPRINT.md).

## 1. Principles

- Calm, clean, welcoming; appropriate for a prayer ministry.
- One primary action per screen ("Continue praying", "Start praying").
- No technical words for users: never "credits", "Melissa", "cache",
  "budget", "API". Server reasons are mapped to plain sentences in
  `OwnerDiscoveryService.messageFor` (`lib/core/data/owner_discovery.dart`).
- Recorded property owners are **not** residents: labelled
  "Property Owner (Public Record)" with "The owner may not live here."; the
  user's own name for a home stays private and separate
  (`users/{uid}/household_status/{id}.residentName`).
- Never a misleading success message: a failed save shows an error snackbar
  (`SnackbarService.showError` + `FirebaseErrorMapper`).

## 2. Tokens (source of truth: code)

### Color — `lib/core/constants/app_colors.dart`

| Token | Hex | Use | Contrast on white |
|---|---|---|---|
| `primaryNavy` | #1B2A4A | brand, headings, primary buttons | 14.1:1 ✅ |
| `primaryGold` | #C9A24B | accents, highlights | 2.4:1 ⚠️ decoration only, never body text |
| `textPrimary` | #0F172A | body | 17.9:1 ✅ |
| `textSecondary` | #64748B | secondary text | 4.8:1 ✅ AA |
| `textMuted` | #94A3B8 | icons, placeholders | 2.6:1 ⚠️ not for essential text |
| `background` / `surface` | #F8FAFC / #FFFFFF | screens / cards | — |
| `border` | #E2E8F0 | card and input borders | — |
| `success` / `danger` / `warning` / `info` | #22C55E / #EF4444 / #F59E0B / #3B82F6 | states (always with an icon or text, never color alone) | — |

**Dark mode:** a `darkTheme` exists (`lib/core/theme/app_theme.dart`) but
the app runs `themeMode: ThemeMode.light` (`lib/main.dart`). Dark mode is
not offered — known debt, see §8.

### Typography — `lib/core/constants/app_typography.dart` (Inter)

| Style | Default | Typical use |
|---|---|---|
| `heading` | 24 / w700 | screen and card titles (17–24 sp) |
| `subheading` | 18 / w600 | section titles |
| `body` | 14 / w400 | paragraphs, messages (12.5–14 sp) |
| `label` | 12 / w600 | chips, buttons, captions |

Sizes go through `flutter_screenutil` (`.sp`, `.h`, `.w`, `.r`), so they
scale with the device. System text scaling is respected.

### Spacing, radius, elevation

- Spacing steps used across screens: 4, 6, 8, 10, 12, 14, 16, 20, 24 (`.h/.w`).
  Screen gutter 16–20; card padding 14–20.
- Radius: inputs/cards 14–18, sheets 24 (top), pills 20.
- Flat design: 1 px `border` instead of shadows on cards.

## 3. Components (`lib/shared/widgets/`)

| Component | File | Notes |
|---|---|---|
| Primary button | `buttons/app_primary_button.dart` | 52 dp tall (≥ 48 dp target), loading state, disables while `isLoading` |
| Outline / back buttons | `buttons/app_outline_button.dart`, `app_back_button.dart` | |
| Text / phone / search inputs | `inputs/app_text_field.dart`, `app_phone_input_field.dart`, `app_search_field.dart`, `address_autocomplete.dart` | US address suggestions; GPS button |
| Chips / segmented switch | `inputs/option_chips.dart`, `app_segmented_switch.dart` | daily goal, map/list |
| Notice card (empty / unavailable / partial) | `layout/collapsing_header_scroll_view.dart` (`AppNoticeCard`) | icon + title + message + actions |
| Empty / error states | `states/app_empty_state.dart`, `app_error_state.dart` | |
| Dialogs | `dialogs/app_confirmation_dialog.dart`, `app_loading_dialog.dart`, `resident_name_dialog.dart` | |
| Household row / detail | `household/household_row.dart`, `bottom_sheets/household_detail_bottom_sheet.dart` | owner label rules above |
| Progress ring | `household/progress_ring.dart` | daily goal |
| Map | `map/household_osm_map.dart` | OpenStreetMap tiles with attribution |
| Bottom navigation | `navigation/app_bottom_navigation_bar.dart` | Home · Neighborhood · Prayer List · Follow-up · Profile |
| **Primary location help (new)** | `lib/features/profile/presentation/widgets/primary_location_help.dart` | read-only neighborhood sheet + "Contact support" (replaces every "Change home address") |

## 4. Navigation

`Splash → (Onboarding) → Sign in / Sign up → Verify email (password accounts)
→ Location setup (only if no saved location) → Main tabs`. Routes:
`lib/routes/app_pages.dart`. The main tabs are a bottom navigation bar; no
nested tab stacks. Detailed flow: [APP_FLOW.md](APP_FLOW.md).

## 5. Screen specifications (what changed 2026-11-24 in **bold**)

| Screen | Content | Fixed-location changes |
|---|---|---|
| Welcome / onboarding | purpose: pray for the households around you | unchanged |
| Location setup (`location_setup_screen.dart`) | 1 address or GPS → 2 confirm pin (drag) → preview nearby homes (**Overture only, never Melissa**: `preview: true`) → daily goal → confirm | **"Choose carefully: this becomes your neighborhood. To change it later, contact support."** above the final button (`_FixedLocationNote`); unavailable-area text no longer says "change your address any time in Profile"; double submit blocked (`isSubmitting`) |
| Home | greeting, neighborhood, today's progress and goal, homes, continue praying | **"Change home address" removed** from the unavailable, empty and no-home states → "Contact support"; no-home state (normally unreachable) → "Set up neighborhood" (location setup) |
| Neighborhood | map / list of the nearest homes around the saved home, owner label rules | **"Look around another place" (header search, banner) and "Set as my home" removed** — signup-only location approved by the client |
| Prayer List | daily goal, mark prayed, next, rounds, history | **"Change home address" → "Contact support"** in the unavailable state |
| Follow-up | visited / invited / follow-up dates and notes | unchanged |
| Profile | profile, prayer preferences, notifications, support, legal, delete account, sign out | **"My address" editor removed** → read-only **"Your neighborhood"** row → sheet with the address, a lock icon, why it is fixed, and "Contact support" |

Every screen covers: loading, success, empty, partial, offline (Firestore
offline cache; owner names need the function), permission denied (GPS:
`openLocationSettings`), timeout / server error (snackbar + retry / pull to
refresh), unavailable area (`AppStrings.areaUnavailable`), and budget-limited
answers ("More homes for this area will be added soon.").

## 6. Accessibility

- Touch targets ≥ 48 dp (primary 52 dp; icon buttons use Material defaults).
- Semantic labels on the new location sheet (address, "Fixed" lock icon);
  ~10 explicit `Semantics`/`semanticLabel` uses in the app overall.
- Color is never the only signal (icons + text on states).
- Known gaps (debt): `textMuted` and `primaryGold` fail AA as text; no
  screen-reader audit has been run on device (VoiceOver / TalkBack).

## 7. Tests

`test/fixed_location_test.dart` (no screen may offer to change the location;
only setup saves one), `test/home_screen_test.dart` (contact support, setup
pointer), `test/owner_discovery_test.dart` (plain messages, no "credit" /
"budget" words), plus the existing widget suites. See
[TESTING_STRATEGY.md](TESTING_STRATEGY.md).

## 8. Debt and next steps

1. Dark mode (theme exists, not enabled; needs contrast review).
2. Raise `textMuted` contrast where it carries information.
3. Device screen-reader pass (VoiceOver, TalkBack).
4. Spanish localisation (the client is a Spanish-speaking church network;
   UI strings are English today).
