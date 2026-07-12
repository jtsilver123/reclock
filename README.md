# Reclock: Jet Lag Planner

**Feel local when you land.**

Reclock turns your flights into a practical, personal plan for sleep, light, caffeine, and
arrival-day recovery — free, private, offline-capable, and honest about what a real traveler
in economy with a job can actually do.

> Your flights are already there. Your jet lag plan appears automatically.
> And when travel changes — delays, missed sleep, a surprise dinner — the plan adapts to
> the trip you're actually having, not the one that was supposed to happen.

## What makes it different

- **Completely free.** No subscription, no ads, no locked features, no account.
- **Automatic.** Import flights straight from your calendar (works with events created by
  Flighty, TripIt, and airline confirmations) or type them in under a minute.
- **Practical, not idealized.** The engine never schedules sleep during boarding, meal
  service, descent, or your daughter's wedding. It caps in-flight sleep at what *you* said
  is realistic, and if you can't sleep on planes at all, it plans quiet rest instead of
  pretending.
- **Adaptive.** Report a delay, a missed light window, or an accidental nap, and the rest
  of the plan is rebuilt from where your body clock actually is — with a plain-English
  explanation of what moved.
- **Simple in the moment.** The home screen shows only **Now / Next / Tonight**. The full
  timeline is one tab away.
- **Private by default.** Everything lives on-device. Calendar parsing is local. Analytics
  are opt-in and anonymous. There is no server.
- **Useful offline.** Plans and notifications are computed and scheduled locally, so
  airplane mode changes nothing.

## Repository layout

```
Reclock.xcodeproj/        Xcode 16 project (filesystem-synchronized groups)
Reclock/                  iOS app target (SwiftUI, iOS 17+)
  App/                    Entry, DI container, root navigation, observable model
  DesignSystem/           Tokens (color/spacing/type) + reusable components
  Features/               Onboarding, Home, Timeline, TripDetail, Explanations,
                          Settings, CheckIn, DevMenu (DEBUG only)
  Services/               EventKit, UserNotifications, HealthKit adapters
ReclockKit/               SwiftPM package: ALL business logic, zero UIKit/SwiftUI
  Sources/ReclockKit/
    CoreModels/           UserProfile, Trip, FlightSegment, PlanAction, JetLagPlan…
    PlanEngine/           The protocol-versioned circadian planning engine
    TripManagement/       Validation + adaptive replanning coordinator
    FlightImport/         Calendar event parsing, itinerary provider protocols
    Notifications/        Pure notification planning (dedupe/quiet hours/caps)
    Persistence/          Atomic JSON store with migration & corruption recovery
    Analytics/            AnalyticsClient protocol, NoOp + thin PostHog client
    HealthIntegration/    SleepDataProvider protocol + pattern analyzer
    Airports/             Bundled 137-airport directory with IANA zones
    TestingSupport/       Demo trips & profiles
  Tests/ReclockKitTests/  63 Swift Testing tests — run on Linux and macOS
ReclockUITests/           XCUITest critical path
docs → *.md               Product, science, privacy, store & test documentation
```

**Why a package?** The entire planning engine compiles and tests on any Swift platform.
CI runs the engine suite on Linux in seconds, and the iOS app is a thin, replaceable shell
around it. If the science evolves, `PlanEngineConfiguration` and `SCIENCE_SPEC.md` change
together, versioned by `ProtocolVersion`.

## Quick start

```bash
# Engine tests (any platform with Swift 6+)
cd ReclockKit && swift test

# The app (macOS + Xcode 16+)
open Reclock.xcodeproj    # scheme "Reclock", ⌘R for the app, ⌘U for all tests
```

See **SETUP.md** for signing, TestFlight, and feature-flag details.

## How the plan works (one paragraph)

Reclock estimates your circadian phase from your habitual sleep, computes the real
time-zone displacement of your itinerary (IANA zones, DST-correct, date-line-safe), and
schedules a nightly shift toward the destination — advancing ~1h/day eastward, delaying
~1.5h/day westward, and going "the long way around" when that's genuinely faster (e.g.
+12h to Singapore is planned as a 12h delay, 8 days instead of 12). Each day it places
light-seeking and light-avoiding windows around your estimated temperature minimum (the
point where light flips direction), fits sleep around flights/meals/commitments, sets a
caffeine cutoff 9h before target bed, and optionally reminds opted-in users about
melatonin timing. Full rules, sources, and limitations: **SCIENCE_SPEC.md**.

## Status

| Area | State |
| --- | --- |
| Plan engine + validators | ✅ implemented, 63 tests green |
| Manual entry + calendar import | ✅ implemented |
| Now/Next/Tonight, timeline, adaptation | ✅ implemented |
| Local notifications w/ actions | ✅ implemented |
| HealthKit sleep pre-fill | ✅ behind opt-in (capability setup in SETUP.md) |
| Email-forwarding import (AwardWallet) | 🚧 scaffolded behind flag, off |
| Cloud sync | 🚧 interface only, deliberately absent in v1 |
| App Store metadata & privacy docs | ✅ drafted |

Key docs: [ARCHITECTURE](ARCHITECTURE.md) · [DECISIONS](DECISIONS.md) ·
[SCIENCE_SPEC](SCIENCE_SPEC.md) · [PRIVACY](PRIVACY.md) · [ANALYTICS](ANALYTICS.md) ·
[APP_STORE_METADATA](APP_STORE_METADATA.md) · [APP_REVIEW_CHECKLIST](APP_REVIEW_CHECKLIST.md) ·
[TEST_PLAN](TEST_PLAN.md) · [SETUP](SETUP.md)

## License & health note

Source available for review; app distribution via the App Store. Reclock provides general
wellness guidance for travel. It does not diagnose, treat, or prevent any condition, and
it is not a substitute for medical advice.
