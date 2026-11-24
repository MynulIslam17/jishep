# Compatibility audit: installed app builds vs the new backend

Status **2026-11-24**. Question: what happens to users who keep an older
build (App Store **1.0.0**, which has the location editor, "Look around
another place" and "Set as my home") once the new rules and functions are
deployed?

The old behaviour is read from git `HEAD` (`lib/core/services/home_address_service.dart`,
`lib/core/data/user_repository.dart`, `neighborhood_controller.dart`,
`profile_controller.dart`). The new behaviour is the working tree, verified by tests.

## 1. Summary

| Old-build action | New backend | User sees | Test |
|---|---|---|---|
| Sign up → location setup (no home yet) | **allowed** (first save) | works as before | `rules.test.js` "old app: location setup write …" |
| Profile › "Change home address" | **refused** by rules (`locationChangeAllowed`) | snackbar **"Address Not Saved — You do not have permission to do that."** The address does not change. | "old app: the removed … editor write is refused" |
| Neighborhood › look around → "Set as my home" | refused (same write) | same snackbar | same |
| Neighborhood › look around (browse only) | no backend change: it uses the free Overture cells; the old app never asked `discoverOwners` for that point | still works in the old build | `blueprint.test.js` (a forged point → `location_not_authorized` anyway) |
| Owner names for the home (`discoverOwners` with the saved point) | served (the point is within 250 m of the pinned home) | same names | `blueprint.test.js` "no coordinates or the saved ones (old app)" |
| Paid discovery from an old build | refused before any credit: no App Check token → `limited: 'app_check'` (the old app ignores `limited`) | what is stored, nothing new | `resilience.test.js` App Check tests |
| Prayer, follow-up, daily goal, radius, avatar, notifications, delete account | unchanged | works | `rules.test.js` (existing suites + compatibility test) |
| Offline edit of the address | queued locally, then refused at sync; the SDK rolls the local change back | address briefly shows the new value offline, then returns | Firestore SDK behaviour (pending write rejected → reverted) |

No old-build path can move a saved home, spend credits, or lose data.

## 2. Details

**Write shapes.** The old editor sends `set({address, latitude, longitude,
updatedAt: serverTime}, merge)`. The old setup sends the same plus
`searchRadiusKm`, `dailyPrayerTarget` and optional `prayerIntention`. The new
rules accept the location fields only while the profile has no
latitude/longitude. Re-sending identical values is a no-op, so it is accepted.
`locationConfirmedAt` / `locationVersion` are optional, so the old setup
write (without them) is valid.

**Error handling in the old build.** Both old editor paths `await` the write
inside `try/catch` and call `SnackbarService.showError('Address Not Saved',
FirebaseErrorMapper.message(error))`. `bindUser(updated)` runs only after a
successful write, so the old app does not switch its neighborhood on
failure. The wording is generic, and it cannot be changed in a shipped
binary. The next build removes the editor entirely and says "To change it,
contact support".

**Existing users.** Anyone who already has coordinates is locked
automatically. No data migration is needed. The first `discoverOwners` call
pins `primary_locations/{uid}` from `users/{uid}`.

**Corrections.** A user who has really moved contacts support. The operator
runs `functions/tool/location_admin.js correct` (audited, at most 2 per year).
The old build picks up the new home on its next start, because it reads
`users/{uid}`.

## 3. App Check and old builds

| Setting | Old builds (no App Check) | New builds |
|---|---|---|
| `MELISSA_REQUIRE_APP_CHECK=true` (soft, planned) | stored data, no paid lookups | everything |
| `ENFORCE_APP_CHECK=true` (functions, hard) | **owner names stop** (every callable rejected) | everything |
| Firestore App Check enforcement | **app unusable** (every read/write rejected) | everything |

So hard enforcement waits until old builds are retired: a forced-update
prompt, or store analytics showing old versions are below about 1 %
([APP_CHECK.md](APP_CHECK.md) §4).

## 4. Recommendations

1. Ship the next build (no editor, App Check) soon after the backend deploy.
2. Optional: a minimum-version check (e.g. a `config/app` doc read at start)
   so future breaking changes can show "please update" instead of a generic error.
3. Keep `ENFORCE_APP_CHECK=false` and Firestore unenforced until then.
