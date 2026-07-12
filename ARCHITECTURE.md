# ARCHITECTURE

## Shape

Two layers, one direction of dependency:

```
┌────────────────────────────── iOS app (SwiftUI, iOS 17+) ──────────────────────────────┐
│  Views (Features/…)  ←→  AppModel (@Observable, @MainActor)  →  Dependencies (DI root) │
│        │                        │                                    │                 │
│        │                        ▼                                    ▼                 │
│        │            platform adapters: EventKitCalendarImporter,                       │
│        │            LocalNotificationScheduler, HealthKitSleepProvider                 │
└────────┼────────────────────────────────────────────────────────────────────────────---┘
         ▼  value types + protocols only
┌──────────────────────────── ReclockKit (SwiftPM, Foundation-only) ─────────────────────┐
│  CoreModels · PlanEngine · PlanValidator · PlanCoordinator · NotificationPlanner       │
│  FlightEventParser · TripValidator · JSONStore · AnalyticsClient · AirportDirectory    │
└─────────────────────────────────────────────────────────────────────────────────────---┘
```

- **ReclockKit never imports SwiftUI/UIKit/EventKit/UserNotifications/HealthKit.** It
  builds and tests on Linux; CI proves it every push. Every product behavior that matters
  (planning, validation, replanning, parsing, notification timing, persistence) lives here.
- **The app is adapters + presentation.** Platform frameworks are wrapped in protocols
  (`CalendarImporting`, `NotificationScheduling`, `SleepDataProvider`,
  `AppStatePersisting`) and injected through one composition root (`Dependencies`),
  so previews/UI tests swap them wholesale (`Dependencies.preview()`, `-reclock-uitest`).

### Mapping to the module list in the product brief

| Brief module | Where it lives |
| --- | --- |
| App, DesignSystem, PlanPresentation, Settings | `Reclock/App`, `Reclock/DesignSystem`, `Reclock/Features/*` |
| CoreModels, TripManagement, PlanEngine, Persistence, Analytics, TestingSupport | same-named folders in `ReclockKit/Sources/ReclockKit/` |
| FlightImport, CalendarImport | parsing logic in kit `FlightImport/`; the EventKit adapter in `Reclock/Services/CalendarImport` |
| Notifications | planning in kit `Notifications/`; delivery in `Reclock/Services/NotificationDelivery` |
| HealthIntegration | protocol + analyzer in kit; HK adapter in `Reclock/Services/HealthIntegration` |
| Networking | deliberately minimal: the thin PostHog client in kit `Analytics/` is the only network code in the product |
| Privacy | `Reclock/PrivacyInfo.xcprivacy`, Settings privacy panel, PRIVACY.md |

One package with folders (not 12 micro-packages): identical testability, faster builds,
and protocol boundaries enforce the same discipline. See DECISIONS.md #3.

## The engine (the part worth reading twice)

`PlanEngine.generatePlan(trip:profile:currentState:)` is **pure and deterministic**:
no `Date()`, no randomness, same inputs → byte-identical plan (IDs included — they're
FNV-hashed from trip ID + rule + day index, which is what makes notification
cancellation and plan merging exact).

Pipeline per generation:

1. **Itinerary sanity** — segments ordered, arrivals after departures, zones resolvable;
   friendly errors otherwise.
2. **Stint decomposition** — segments split wherever ground time ≥ 48h. Each stint's final
   arrival zone is an adaptation target. One-way = 1 stint; round trip = 2; multi-city =
   N. Open-jaw falls out naturally (last stint's zone just isn't home).
3. **Strategy choice** — `automatic` anchors to home time for ≤ 2-night stays with ≤ 5h
   shifts (CDC-style short-trip guidance), else full adaptation. User can override either
   way per trip.
4. **Shift selection** — signed zone delta normalized to (−12, +12]; eastward ≥ 9h also
   evaluates the antidromic path (delay 24−Δ) and takes whichever completes sooner at the
   configured rates.
5. **Night schedule** — the traveler's state is one number `B` (hours advanced from home
   baseline). Each night steps `B` toward the active stint target: pre-departure nights at
   the gentle rate, en-route/arrival nights at full rate, snapping to a per-date,
   DST-correct wall-clock target (never a fixed offset). From `B` come bed/wake/CBTmin
   estimates per night; a practical clamp keeps scheduled bedtimes inside 20:30–01:30
   local (never in anchor mode, never mid-flight).
6. **Action building** (`PlanEngine+Actions.swift`) — per day: sleep fitting (subtract
   airport buffers, takeoff/descent windows, meal services unless the user skips them,
   commitments, the post-landing daytime gate; cap by the user's realistic in-flight
   max; widen the window when a night gets squeezed), PRC-anchored light seek/avoid
   windows (direction is **per-night**, so the return leg of an eastward trip correctly
   flips to delay behavior), stay-awake anchor on westward-style arrival evenings,
   ≤ 30-min nap with an 8h bed buffer that dodges commitments, caffeine window + cutoff
   (bed − 9h), optional melatonin reminders (opt-in, advance days only, disclaimer
   embedded), wind-down, and comfort actions (hydrate/move/meals) explicitly framed as
   comfort, not circadian levers.
7. **Density caps & rounding** — per-intensity caps drop lowest-impact optional actions;
   all windows round to 5 minutes (no false precision).
8. **Validation** — `PlanValidator` re-checks the ten hard rules (contradictory overlaps,
   sleep in blocked windows, caffeine past cutoff, melatonin when opted out, DST-invalid
   dates, post-trip actions, duplicates, arrival-day guidance present, in-flight sleep cap,
   never-sleeper protection). The app refuses to show a plan that fails with errors.

### Adaptive replanning

`PlanCoordinator`:

- `estimateState(plan:trip:events:asOf:)` — folds completion states into an achieved-shift
  estimate using compliance credits (done 1.0 / unknown 0.75 / missed 0.4 per night's
  scheduled delta) plus a sleep-debt tally from explicit reports. Deliberately simple,
  fully deterministic, documented in SCIENCE_SPEC.md — **no opaque learning touches the
  protocol**.
- `replan(...)` — regenerates from the estimated state, then `merge`: actions that ended
  before `asOf` keep their recorded history (pending ones become `expired`), the future
  comes from the fresh plan, deterministic IDs prevent duplicates, revision increments.
- `describeChanges(...)` — compares the next sleep/light/caffeine anchors and emits the
  human sentences shown in the home banner ("Your next sleep window moved 2 hours later.").

### Notifications

`NotificationPlanner` (kit, tested) decides *what and when*: per-type templates, quiet-hours
shifting (sleep-adjacent types exempt), 5-minute dedupe, per-intensity daily caps, IDs of
the form `r<revision>/<actionID>/<kind>`. `LocalNotificationScheduler` (app) merely
delivers: registers categories (Done / Snooze 30 / Couldn't), schedules ≤ 60 pending
(system limit is 64), cancels by ID prefix when a revision or action dies. Everything is
scheduled up front — **no background refresh is required for delivery**, which is what
keeps airplane mode a non-event.

### Persistence

`JSONStore` (actor): single versioned envelope `{schemaVersion, payload}` written
atomically. Corrupt file → quarantined as `state.corrupt.json`, fresh state returned, no
crash. Migrations run stepwise (`v0→v1` shipped as the pattern + test). The same encoder
powers the user-facing "Export my data" feature — the export *is* the store.

## Data flow for the two key gestures

**Add trip:** AddTripFlow → segments (parser or manual) → `TripValidator` →
`AppModel.addTrip` → `PlanEngine.generatePlan` → `PlanValidator` → persist →
`NotificationPlanner` → scheduler. Any failure surfaces a friendly alert; nothing
half-saves.

**"Couldn't do it" on a sleep/light action:** completion recorded → per-action
notifications cancelled → `estimateState` → `replan` → merged plan persisted → old
revision's notifications cancelled by prefix, new set scheduled → change banner shown.

## Testing strategy

- **63 kit tests** (Swift Testing) cover direction math, date line, DST edge weeks,
  antidromic choice, every reality constraint, parser formats, notification policies,
  persistence (incl. corruption/migration), and replanning — all on fixed dates and
  explicit zones, immune to the machine's locale.
- **UI tests** cover the critical path: onboarding → home; seeded trip → complete action;
  timeline; delay report; delete trip; privacy controls.
- **Determinism test** locks the engine: same inputs must produce identical plans.

## Future-proofing

- `ItineraryParsingProvider` (+ mock + AwardWallet skeleton) is the seam for forwarded-email
  import; `FeatureFlags.emailForwardingEnabled` gates all UI.
- Cloud sync would implement `AppStatePersisting` against a backend and merge — the app
  never talks to storage except through that protocol.
- `ProtocolVersion` stamps trips and plans; a future v2 protocol migrates cleanly and can
  be A/B-documented in SCIENCE_SPEC.md.
