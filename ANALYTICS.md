# ANALYTICS

## Posture

- Default client: `NoOpAnalyticsClient`. The app is fully functional with analytics
  disabled, and **ships disabled**.
- Opt-in toggle lives in Settings → Privacy. Turning it on activates the thin
  `PostHogAnalyticsClient` **only if** the owner has configured a key at build time —
  no key is committed to this repository.
- Identity: a locally generated random anonymous ID; toggling analytics off and on
  rotates it. No IDFA, no fingerprinting, no linkage to any account (none exist).
- Transport: direct HTTPS `POST /batch` to PostHog with a closed JSON payload —
  deliberately **not** the PostHog SDK (no session replay, no autocapture, no device
  graph). Failed batches are dropped, never queued to disk.

## Event dictionary (closed set — adding one requires editing `AnalyticsEvent`)

| Event | Properties | Question it answers |
| --- | --- | --- |
| app_opened | – | DAU/retention envelope |
| onboarding_started / onboarding_completed | – | funnel drop-off |
| import_method_selected | method ∈ {calendar, manual} | which import path wins |
| calendar_permission | granted | permission friction |
| trip_imported | source, segments, tz_delta | calendar-detection success |
| trip_manually_entered | segments, tz_delta | manual path share |
| plan_generated | strategy, direction, shift_hours, intensity | plan mix (e.g. % anchor mode) |
| plan_mode_selected | intensity | Easy/Balanced/Max preference |
| notification_permission | granted | reminder opt-in rate |
| action_completed / action_skipped | type, priority | which recommendations survive reality |
| plan_recalculated | trigger ∈ {delay_reported, missed_action, manual, trip_edited, profile_changed} | adaptivity usage |
| flight_delay_reported | delay_minutes | delay magnitudes to design for |
| timeline_viewed | – | depth of engagement |
| post_trip_survey_completed | severity, usefulness, adherence | outcome proxy |
| review_prompt_shown | – | prompt hygiene |

**Forbidden forever** (enforced by the closed enum): calendar text, health samples,
booking references, names, email content, notes, precise locations, exact timestamps of
user sleep. Route granularity is limited to the signed hour delta.

## Internal dashboard spec (when analytics are enabled)

1. **Activation funnel:** app_opened → onboarding_completed → first plan_generated
   (target: > 60% of openers reach a plan on day 1).
2. **Import quality:** trip_imported vs trip_manually_entered; calendar_permission grant
   rate; detected-but-deselected ratio (future event) — drives parser investment.
3. **Plan realism:** action_completed / (completed + skipped) by action type & priority.
   A must-do type under ~60% completion is mispriced — candidate for [REVIEW] tuning via
   SCIENCE_SPEC process.
4. **Adaptivity value:** % of trips with ≥ 1 plan_recalculated; distribution of triggers.
5. **Outcomes:** survey severity × adherence cohort view; usefulness trend per protocol
   version (versions are in plan_generated's implicit release dimension).
6. **Mode mix:** anchor vs adapt share by tz_delta bucket — validates the short-trip rule.

Review cadence: monthly; any protocol-constant change proposal flows through
SCIENCE_SPEC.md's review gate, never silently.
