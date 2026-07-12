# TEST_PLAN

## Layers

| Layer | Tooling | Where it runs | Count |
| --- | --- | --- | --- |
| Engine/unit (all business logic) | Swift Testing (`swift test`) | Linux CI + macOS CI + local | 67 |
| UI critical path | XCUITest | macOS CI simulator | 6 |
| Manual device pass | APP_REVIEW_CHECKLIST.md | Before each submission | — |

Principles: fixed dates (2026-09-15 reference et al.), explicit IANA zones everywhere,
zero dependence on machine locale/zone/clock; the engine is pure, so every scenario is a
plain function call; every generated plan in tests must pass `PlanValidator`.

## Engine coverage map (implemented ↔ brief requirements)

**Directions & zones** — eastward (JFK→HEL +7 advance), westward (LHR→JFK −5 delay),
1-hour (JFK→ORD), same-zone (JFK→MIA), 12-hour antidromic (JFK→SIN via FRA plans a 12h
delay), date line west (LAX→HND −8), date line east with local-time "arrival before
departure" (SYD→SFO +7), normalization table incl. ±12 and ±17.

**DST** — London↔NY during the Oct gap week (offset −4 not −5, asserted), US
spring-forward nonexistent 02:30 resolves to a valid instant, plan spanning the EU
fall-back keeps sane local bedtimes (validator + local-hour assertions).

**Reality constraints** — no sleep in boarding/takeoff/descent buffers across all 10
demo trips; meal-service windows block sleep unless the profile opts out; in-flight
sleep ≤ stated max (3h cap case asserted); "never sleeps on planes" ⇒ zero in-flight
sleep actions, quiet-rest fallback, first-night protection; wedding commitment never
overlapped by sleep/nap; nap dodges commitments (48h-London client meetings); practical
bedtime clamps; post-landing daytime gate (red-eye Paris case asserts avoid-light before
seek-light, seek after CBTmin).

**Preferences** — caffeine opt-out removes all caffeine actions; caffeine windows never
cross their cutoff (blanket across demo trips); melatonin absent unless opted in, always
optional-priority, disclaimer text asserted; intensity changes density and Easy has no
pre-departure shift; willingness caps pre-trip days (Paris test uses `.none`).

**Modes** — short 2-night trip anchors to home time (no light actions, sleep protected);
forced full-adapt override honored; anchor never practical-clamps.

**Adaptivity** — delay replan: revision bump, change messages, no sleep in the new
boarding window, merged plan validates; completed past actions preserved verbatim;
missed sleep lowers achieved-shift estimate vs all-done (strict inequality) and replan
stays valid; sleep-debt events raise debt and enable nap; no-op replan says so.

**Determinism** — same inputs ⇒ identical plans (IDs included).

**Notifications** — deterministic revision-scoped IDs; new revision = disjoint ID set
(prefix cancellation); disabled prefs ⇒ empty; optional actions gated by opt-in;
completed actions silent; quiet hours respected for non-sleep types (asserted across
the whole schedule) while sleep/wind-down stay exempt; per-intensity daily caps; only
future notifications after a cutoff instant.

**Parsing** — Flighty ("Flight to San Francisco (DL 423)"), TripIt ("BA 178 LHR to
JFK"), arrow routes with booking refs, plain-language ("Flight to Tokyo" + boarding
notes), rejection set (dinner, dentist, "Gate 21 Brewery", week-long conference, rental
car), cross-app duplicate collapse, segment conversion completeness rules, provider
scaffold behavior (mock round-trip; AwardWallet reports not-configured).

**Persistence** — round-trip equality, fresh start, corruption quarantine + recovery,
v0→v1 migration, wipe (incl. quarantine), export validity, ISO-8601 coding stability.

**Trip validation** — arrival-before-departure blocks with friendly text; implausible
block times; overlapping segments; unknown airport advisory-only; unknown zone blocking.

## UI tests (XCUITest, launch args `-reclock-uitest` / `-reclock-seed-demo`)

1. Onboarding → completed profile → empty home (covers steps 1–4 of the brief's path).
2. Seeded landing day → Now card visible → Done completes (steps 5–7).
3. Timeline shows phase headers.
4. Delay report: +2h quick action → Update plan → UI returns coherent (steps 8–9).
5. Delete trip → confirmation → empty state (step 10).
6. Settings privacy controls exist (export/delete).

## Gaps & manual mitigations (honest list)

- Notification *delivery* and interactive actions are OS-level: covered by the device
  checklist, not simulator asserts.
- HealthKit provider logic is unit-tested at the analyzer level
  (`SleepPatternAnalyzer`); the HK query path needs a capability-enabled device pass.
- Localization is v1 English; pseudo-localization pass scheduled with the string
  catalog work.
- Performance: plans are O(days×actions), instant in practice (63 tests in ~0.2 s
  including full plan generations); no dedicated perf suite yet.

## How to run

```bash
cd ReclockKit && swift test --parallel          # engine, any platform
xcodebuild test -project Reclock.xcodeproj \
  -scheme Reclock -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO                        # kit tests + UI tests
RECLOCK_DUMP=1 swift test --filter PlanDumpDebug # human-readable plan dumps
```
