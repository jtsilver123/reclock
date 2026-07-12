# APP_REVIEW_CHECKLIST

Walk top to bottom on a physical device before every submission. ☐ = verify each time.

## Functionality

- ☐ Fresh install: onboarding → add manual trip (JFK→HEL fixture data) → plan appears
  with Now/Next/Tonight populated.
- ☐ "See an example" on first launch loads the demo landing-day trip.
- ☐ Calendar import: grant flow, detection list shows only flight-shaped events,
  deselect works, import builds a trip.
- ☐ Calendar denied: friendly fallback screen; manual entry one tap away; re-enable
  path text correct (iOS Settings → Privacy → Calendars).
- ☐ Notifications: permission asked only from the in-app card after a plan exists;
  actions Done / Snooze 30 min / Couldn't do it all work from a delivered notification.
- ☐ Notifications denied: Today tab functions as checklist; Settings shows enable-later
  guidance; no repeated system prompts.
- ☐ Location: "Estimate from my location" prompts only on tap; sets a sensible minutes
  value; denied ⇒ friendly note + presets still work; button hidden in Local-only mode;
  no location prompt anywhere else in the app.
- ☐ Delay report (+2h) rebuilds future plan, shows change banner, reschedules reminders
  (verify in Settings → Notifications → Reclock pending list via device console or by
  waiting for next fire).
- ☐ "Couldn't do it" on a sleep action triggers recalculation with explanation.
- ☐ Post-trip survey submits and persists; trip marked completed.
- ☐ Delete trip removes plan + pending notifications; Delete all data returns app to
  first-run state (verify store file gone).
- ☐ Airplane mode: full plan, timeline, completion, and already-scheduled notifications
  all work with radios off.

## Quality gates

- ☐ Two device sizes (e.g. iPhone SE-class small + Pro Max) — no clipped layouts.
- ☐ Dark mode: every screen legible; Now card tints correct.
- ☐ Dynamic Type at XXL and AX1: home, timeline, onboarding remain usable (text wraps,
  no truncated critical info).
- ☐ VoiceOver: Now card reads action, window, priority; buttons have labels; priority
  badges and glyphs are not color-only (labels present).
- ☐ Reduce Motion honored (no parallax/large animated transitions).
- ☐ 12h and 24h locale time formats render correctly (switch region).
- ☐ No crashes in a 15-minute exploratory pass; console free of warnings/errors spam.
- ☐ Xcode build with `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` passes (CI enforces).

## Compliance & hygiene

- ☐ Works with no account (none exists), no HealthKit, no calendar, no network.
- ☐ Privacy labels match behavior: default build = Data Not Collected; analytics toggle
  present but no key configured.
- ☐ PrivacyInfo.xcprivacy present in bundle; declarations match code (no flagged APIs,
  no tracking).
- ☐ Permission strings read correctly in context (calendar, health).
- ☐ Links live: reclock.app/privacy, /support, /terms (publish before submitting).
- ☐ No test keys, no dev menu (release build hides Developer section — verify), no
  placeholder text ("lorem", "TODO", "reclock.app" pages published), no dead buttons.
- ☐ Metadata claims audit: no medical/validation claims; no partner-integration claims.
- ☐ Version/build bumped; What's New written; screenshots current.

## Submission package

- ☐ App Store Connect privacy questionnaire = PRIVACY.md table.
- ☐ Review notes pasted from APP_STORE_METADATA.md.
- ☐ Export compliance: uses only exempt HTTPS (ITSAppUsesNonExemptEncryption=NO already
  in Info).
- ☐ TestFlight external group notes updated.
