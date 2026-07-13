# SETUP

## Requirements

- **Engine (ReclockKit):** Swift 6.0+ on macOS or Linux. No other dependencies.
- **App:** macOS 14+, Xcode 16.x (project uses filesystem-synchronized groups,
  `objectVersion 77`). iOS 17.0 deployment target, iPhone.

## Build & test

```bash
# Engine only — fast, works everywhere
cd ReclockKit
swift build
swift test --parallel

# Full app
open Reclock.xcodeproj
# Scheme: Reclock → ⌘B build, ⌘R run, ⌘U runs ReclockKitTests + ReclockUITests
```

CLI equivalents:

```bash
xcodebuild build -project Reclock.xcodeproj -scheme Reclock \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO

xcodebuild test -project Reclock.xcodeproj -scheme Reclock \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```

The first open resolves the local `ReclockKit` package automatically (no network needed).

## Signing

1. Select the **Reclock** target → Signing & Capabilities.
2. Choose your team; bundle ID defaults to `app.reclock.ios` — change it to one your
   account owns (also update `PRODUCT_BUNDLE_IDENTIFIER` for the UITests target:
   `<your-id>.uitests`).
3. Automatic signing handles the rest. `Reclock.entitlements` (time-sensitive
   notifications + HealthKit) is already wired via `CODE_SIGN_ENTITLEMENTS`.

## Flight-number lookup (optional, key-gated)

"Search by flight number" activates only when a schedule API key is present — the app is
complete without it (manual entry pre-estimates arrival times from the route).

1. Get an AeroDataBox key via RapidAPI (free tier is fine for testing).
2. Create `Secrets.xcconfig` (already gitignored) next to the project:
   `RECLOCK_AERODATABOX_KEY = your-key-here`
3. Set it as the project's configuration file (Project → Info → Configurations), and add
   a build setting on the Reclock target:
   `INFOPLIST_KEY_ReclockAeroDataBoxKey = $(RECLOCK_AERODATABOX_KEY)`
4. Rebuild. The "Search by flight number" option appears in Add a trip.

Privacy: requests contain only the flight number and date (see PRIVACY.md).

**Validated against the live API (2026-07):** the response mapping in
`AeroDataBoxScheduleProvider.parse` is unit-tested against a verbatim captured payload
(AY16 JFK→HEL), including terminal extraction and tolerance of extra fields. Costs on
the free Basic plan: **one flight-number lookup = 2 API units → ~300 lookups/month
free** (the balance endpoint is free and shows remaining units). Mapping is defensive —
any future schema drift degrades to "not found" with manual entry one tap away.

⚠️ Key hygiene: never commit the key. `Secrets.xcconfig` is gitignored for exactly this;
if a key is ever pasted into a chat, issue tracker, or log, rotate it in the RapidAPI
dashboard (takes seconds, the old key dies instantly).

## Feature flags (`ReclockKit/Sources/ReclockKit/FlightImport/ItineraryParsingProvider.swift`)

| Flag | Default | Meaning |
| --- | --- | --- |
| `FeatureFlags.healthKitEnabled` | `true` | Compiles the HealthKit provider. The entitlement ships in `Reclock.entitlements`; the feature still activates only if the user opts in, and if the entitlement is ever stripped the provider reports "unsupported" and the UI hides itself. |
| `FeatureFlags.emailForwardingEnabled` | `false` | AwardWallet email-parsing scaffold. Requires a commercial agreement + server proxy. Leave off. |
| `FeatureFlags.cloudSyncEnabled` | `false` | Interface exists; no backend in v1. |

### HealthKit (ships enabled)

The HealthKit + Time Sensitive Notifications entitlements live in
`Reclock.entitlements` (wired via `CODE_SIGN_ENTITLEMENTS`), and both capabilities
are enabled on the App ID. `NSHealthShareUsageDescription` is set via build settings,
the provider is wired behind `SleepDataProvider`, everything is opt-in at runtime,
and the app functions identically if the user declines.

## Dev conveniences

- **Hidden dev menu:** Settings → Developer (DEBUG builds only) loads any of the 10 demo
  trips positioned so "today" is landing day.
- **UI-test launch args:** `-reclock-uitest` (isolated temp store, mock calendar, no-op
  notifications) and `-reclock-seed-demo` (preloads the Helsinki landing-day trip).
- **Engine plan dump:** `RECLOCK_DUMP=1 swift test --filter PlanDumpDebug` prints two full
  human-readable plans for eyeballing.

## TestFlight (from your Mac)

1. Set your team + bundle ID (above); bump `MARKETING_VERSION` if needed.
2. Product → Archive (scheme Reclock, Any iOS Device).
3. Distribute → App Store Connect → Upload. `ITSAppUsesNonExemptEncryption` is already
   `NO`, so no export-compliance questionnaire blocks the build.
4. In App Store Connect: add the TestFlight description from `APP_STORE_METADATA.md`
   (§TestFlight) and invite testers.
5. Before submission proper, walk `APP_REVIEW_CHECKLIST.md` top to bottom on a device.

## TestFlight from CI (no Mac needed, one-time setup)

The **TestFlight** workflow (Actions tab → TestFlight → Run workflow) archives, signs via
Apple's cloud-managed certificates, and uploads — entirely on GitHub's macOS runners.

One-time setup:

1. **App record:** App Store Connect → Apps → “+” → New App, with your bundle ID
   (default `app.reclock.ios`, or set repo variable `RECLOCK_BUNDLE_ID`).
2. **API key:** App Store Connect → Users and Access → Integrations →
   App Store Connect API → Team Keys → “+”. Role: **App Manager**. Download the `.p8`
   (only downloadable once).
3. **Repo secrets** (Settings → Secrets and variables → Actions):
   - `ASC_KEY_ID` — the key's ID (e.g. `2X9R4HXF34`)
   - `ASC_ISSUER_ID` — the issuer UUID shown above the key list
   - `ASC_API_KEY_P8` — the full contents of the `.p8` file
   - `APPLE_TEAM_ID` — your 10-character team ID (Membership page)
4. **Optional — flight-number search in TestFlight builds:** add repo secret
   `RECLOCK_AERODATABOX_KEY` (the AeroDataBox key). Without it the build works fully;
   the search option simply hides itself. Local builds keep using `Secrets.xcconfig`.
5. Run the workflow. Build number defaults to the run number; the upload appears in
   TestFlight after Apple's ~5–15 min processing.

Signing works with **zero registered devices**: the archive is built unsigned
(`CODE_SIGNING_ALLOWED=NO` — automatic signing would otherwise demand a development
profile, which requires a registered device), and `-exportArchive` re-signs it for
the App Store using the cloud-managed distribution certificate via the API key.
No certificates, profiles, or devices to manage from a Mac.

Because the export re-sign derives entitlements from what the app already carries,
the workflow ad-hoc-signs the archived .app with `Reclock.entitlements` before the
export step and fails the run if either entitlement is missing from the final IPA
(pattern proven in jtsilver123/cini, where the re-sign once silently dropped
Sign in with Apple). Add any future entitlement to `Reclock.entitlements` and to
the verify list in `.github/workflows/testflight.yml`.

## Backup & sync backend (Supabase)

Auth + backup run against the Supabase project `Reclock` (`txqysnyfrlizxatbimpb`,
us-east-1, free tier). The URL and publishable key are embedded in
`Reclock/Services/Auth/SupabaseAuth.swift` — safe by design; row-level security is
the guard. Schema and the `delete-account` edge function are managed as migrations
in the Supabase project itself.

One-time setup still needed from the account owner:

1. **Apple provider:** Supabase dashboard → Authentication → Sign In with Apple →
   enable, and add `app.reclock.ios` to **Client IDs** (native flow needs no secret).
2. **App ID capability:** developer.apple.com → Identifiers → `app.reclock.ios` →
   check **Sign In with Apple** → Save (profiles regenerate automatically on the
   next CI build).
3. **Google (optional):** Google Cloud Console → APIs & Services → Credentials →
   Create OAuth client ID → type **iOS**, bundle `app.reclock.ios`. Then
   (a) repo secret `RECLOCK_GOOGLE_CLIENT_ID` = the client ID, and
   (b) Supabase dashboard → Authentication → Google → enable and add the same
   client ID to **Authorized Client IDs**. Without the secret the Google button
   simply never appears (Apple-only).

## Credentials still required (account owner)

- Apple Developer team for signing (nothing else — there is no backend).
- Optional, later: PostHog project key **only** if you decide to ship opt-in analytics
  as ON-by-consent; the code defaults to `NoOpAnalyticsClient` and no key is present in
  the repository.
- Optional, phase 2: AwardWallet commercial API access + a proxy host for email import.

## CI

`.github/workflows/ci.yml` runs:
1. **Linux:** `swift test` for ReclockKit (the whole brain of the app) in a Swift 6 container.
2. **macOS:** `xcodebuild build` (warnings as errors) + kit tests + UI tests on an
   iPhone 16 simulator.
