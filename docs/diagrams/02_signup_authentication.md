# 2. Signup and authentication flow

```mermaid
flowchart TD
  A["Open app — SplashScreen"] --> B{"Firebase user signed in?"}
  B -- No --> C["Onboarding → Sign in / Sign up"]
  C --> C1["Email + password"]
  C --> C2["Google Sign-In"]
  C --> C3["Sign in with Apple"]
  C --> C4["Phone + SMS code"]
  C1 & C2 & C3 & C4 --> D["AuthService.ensureProfile — create users/{uid} if missing, in a transaction"]
  B -- Yes --> D
  D --> E["AuthController.routeAfterSignIn"]
  E --> F{"needsEmailVerification? — password accounts only"}
  F -- Yes --> G["VerifyEmailScreen"]
  G --> E
  F -- No --> H{"profile.hasLocation? — latitude and longitude set"}
  H -- No --> I["LocationSetupScreen"]
  H -- Yes --> J["MainNav: Home / Neighborhood / Prayer List / Follow-up / Profile"]
  I --> J
```

```mermaid
sequenceDiagram
  participant U as User
  participant App
  participant Auth as Firebase Auth
  participant FS as Firestore users/{uid}
  U->>App: sign in / reinstall / new device
  App->>Auth: provider credential
  Auth-->>App: ID token, claims email_verified, sign_in_provider
  App->>FS: ensureProfile — read, create only if absent
  Note over App,FS: Same uid → same profile, same saved location,<br/>same prayer history. No discovery happens here.
  App->>App: routeAfterSignIn
```

**What this shows / where in code.** `lib/features/auth/presentation/controllers/auth_controller.dart` (`loadCurrentProfile`, `routeAfterSignIn`) and `lib/features/auth/domain/services/auth_service.dart` (`ensureProfile`). Signing in, linking a provider, reinstalling or switching devices only reads the existing `users/{uid}`. None of these steps calls Melissa, because discovery runs only when a neighborhood is loaded, and then cache-first. The Firestore rules (`verified()`) block prayer-activity writes from unverified password accounts. The server-side `isVerifiedToken` in `functions/src/owners.js` uses the same claims to gate paid discovery. That gate is local only and not deployed yet.
