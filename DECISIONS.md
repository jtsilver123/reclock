# DECISIONS

Product and engineering judgment calls made while building v1, with reasoning. Items the
product brief left open — or where I deliberately diverged from it — are called out.

## Platform & stack

1. **iOS 17.0 minimum** (brief said "oldest reasonable"). `@Observable`, modern
   `onChange`, `ContentUnavailableView`, and EventKit's granular
   `requestFullAccessToEvents` all land at 17; in mid-2026 iOS 17+ covers the
   overwhelming majority of active devices. Going lower would mean ObservableObject
   plumbing and legacy calendar permission paths for a sliver of users.
2. **No SwiftData.** Persistence is a single atomically-written, versioned JSON document
   behind an actor. Rationale: the dataset is tiny (a few trips), migrations become
   explicit and testable, corruption recovery is trivial to implement and *prove*
   (tests do), the store runs on Linux where the engine tests live, and "export my data"
   falls out for free. SwiftData would add schema/actor complexity for zero user value
   at this scale.
3. **One SwiftPM package with folders, not 12+ micro-modules.** The brief lists many
   modules; they exist as folders + protocol boundaries inside `ReclockKit` plus adapter
   folders in the app. Same testability and discipline, materially faster builds, no
   dependency-graph ceremony. The load-bearing split — pure logic vs. platform — is the
   package boundary itself.
4. **iPhone-only (TARGETED_DEVICE_FAMILY=1) for v1.** A focused phone experience beats a
   stretched iPad layout at launch; iPad support is additive later.
5. **Zero third-party dependencies.** Even analytics is a ~80-line direct HTTP client
   rather than an SDK. Nothing to audit, nothing to disclose beyond our own code, no
   supply-chain risk in a privacy-positioned app.

## Engine & science

6. **Stint model for itineraries.** Ground stays ≥ 48h split the trip into adaptation
   phases with carried body-clock state. This one mechanism handles one-way, round-trip,
   open-jaw, and multi-city without special cases. (< 48h on the ground = layover, planned
   as such.)
7. **Per-night shift direction.** Light/melatonin logic reads the direction of *tonight's*
   remaining shift, never the outbound direction — the return leg of an eastward trip is
   a delay, and early builds that assumed otherwise prescribed morning light on return
   days. Caught by the plan-dump review; now impossible by construction.
8. **Antidromic threshold 9h, decided by days-to-complete.** For eastward shifts ≥ 9h the
   engine compares advancing Δ at the advance rate vs. delaying 24−Δ at the delay rate and
   takes the faster path (e.g. +12h → 12-day advance vs. 8-day delay → delay). Marked
   [REVIEW] in the science spec like every constant.
9. **Practical bedtime clamp (20:30–01:30 local)** keeps scheduled bedtimes humane even
   mid-shift; disabled in anchor mode (odd local hours are the whole point there) and
   in-flight (sleep fitting owns that).
10. **Post-landing daytime gate.** After landing between 05:00–19:00 local, remaining
    "night" is not sleepable — the plan pushes to evening, offering a capped nap instead.
    This is the single most common real-world failure of naive planners.
11. **Avoid-light hands over exactly where seek-light begins** (CBTmin + buffer) on
    arrival mornings. Phase estimates carry uncertainty; "sunglasses until the light
    window opens" is safer and far easier to follow than a gap between two windows.
12. **Melatonin: opt-in, advance-days only, no dosage, disclaimer on every action.**
    `unsure` at onboarding = excluded (safe default). Delay-direction melatonin is off by
    default (`melatoninForDelays=false`) — weaker practical case.
13. **Comfort actions are labeled comfort.** Hydration/meals/movement explicitly state
    they support comfort and routine, not circadian adjustment, per the brief's
    requirement and honest-communication principle.
14. **Compliance-credit state estimation** (done 1.0 / unknown 0.75 / missed 0.4) instead
    of any learned model. Deterministic, explainable, documented; the brief's "no silent
    ML changes to circadian rules" is upheld structurally.
15. **Fixed commitments block sleep, naps, and light windows**; light falls back to
    "brightest indoor spot" guidance rather than disappearing, with an adjustment note.

## Product

16. **Onboarding is 6 screens, not 7** — "import" moved to the moment you add a trip
    (where it has context), keeping first-run under a minute. All brief questions are
    asked; meal-skip preference lives with the plane-sleep questions.
17. **"See an example" seeds a real landing-day trip** (Helsinki demo) rather than a
    static mock — the fastest way to make the value obvious and the same path UI tests
    use.
18. **Offline is a property, not a feature toggle.** There's no server, plans and
    notifications are local; the UI states this (trip screen, settings) rather than
    showing a live "offline status" indicator that would imply a network dependency.
19. **Multiple trips are supported; the "active" trip drives Today/Timeline** (current
    window, else next upcoming). A full trip-switcher UI is v1.1 — data model and store
    already handle any number.
20. **Post-trip survey is stored locally**; only if the user enabled anonymous analytics
    are the numeric ratings (never trip details) reported.

## Store, privacy, ops

21. **Bundle ID placeholder `app.reclock.ios`**, team unset — owner swaps in
    Signing & Capabilities (SETUP.md).
22. **HealthKit ships compiled but capability-gated.** Code + UI are complete behind
    `SleepDataProvider`; the capability isn't in the project so a fresh checkout builds
    and ships with zero special entitlements. Enabling is a 1-step checklist in SETUP.md.
    App Review treats HealthKit strictly; v1 can launch without it and add it in 1.1.
23. **Analytics default: `NoOpAnalyticsClient` and OFF.** The PostHog client exists and
    is documented (ANALYTICS.md), but no key ships in the repo and the toggle is opt-in.
    Privacy manifest currently declares zero collected data — matching actual behavior.
24. **Email-forwarding import is scaffold-only** (`AwardWalletItineraryParsingProvider`
    throws `.notConfigured`; flag off; no UI). No store claims are made about it —
    the brief's caution about unauthorized integration claims is honored by absence.
25. **Notification IDs are revision-scoped** (`r<rev>/<action>/<kind>`) so "cancel by
    prefix" is exact, duplicate-proof, and testable — chosen over bookkeeping stored
    notification lists.
26. **English-only v1, localization-ready.** All user-facing strings are literal and
    extractable (`SWIFT_EMIT_LOC_STRINGS=YES`); engine copy centralization makes a
    future string-catalog pass mechanical. Day labels from the engine are English; they
    move into the app's localization layer when localization lands.

## Known limitations (candid)

- Engine day labels ("Landing day · Sun, Sep 20") are English strings from the kit.
- No live flight-status provider: delays are user-reported (by design for v1 — no
  paid APIs, no accounts; the architecture has the seam).
- The sleep-fit widening pass is single-step (±1.5h); pathological commitment walls can
  still produce short nights — surfaced honestly via adjustment notes.
- `AppModel` regenerates active-trip plans on profile change without prompting; a
  "review changes" diff screen is a v1.1 nicety.
- Flight-number-only entry doesn't look up schedules (no API); the field is stored for
  reference and display.
