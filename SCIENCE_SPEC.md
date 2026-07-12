# SCIENCE_SPEC — Reclock planning protocol v1.0

This document specifies exactly what the plan engine does, why, what is established
science versus implementation assumption, and what must be reviewed by a sleep/circadian
specialist before any public claims stronger than "general wellness guidance."

**Reclock's stance:** conservative, well-trodden interventions (timed light, scheduled
sleep, timed caffeine cessation, optional melatonin information, short-trip home-time
anchoring), delivered with practical constraints and honest uncertainty. Nothing here
diagnoses, treats, or prevents a condition. No claims of clinical validation are made
anywhere in the product or store materials.

---

## 1. Foundations used

| Intervention | Basis (established) | How Reclock uses it |
| --- | --- | --- |
| Timed bright light | Light is the dominant zeitgeber; its phase response curve (PRC) reverses direction around the core body temperature minimum (CBTmin): light after CBTmin advances the clock, light before delays it (Khalsa et al. 2003; Czeisler/Duffy body of work). | Seek/avoid windows are placed relative to an estimated CBTmin, on the correct side for the required shift direction; wrong-side light is actively avoided for the first days. |
| Sleep scheduling | Sleeping at the target zone's night consolidates adaptation and reduces sleepiness; abrupt full-shift attempts often fail (jet lag reviews: Waterhouse et al. 2007, Lancet; Sack 2010, NEJM). | Nightly bed/wake targets step toward destination time at bounded rates, with a practical local-bedtime clamp. |
| Gradual pre-travel shifting | Advancing sleep + morning light for 2–3 days before eastward flights measurably pre-shifts phase (Eastman lab protocols, e.g. Eastman & Burgess 2009). | Optional pre-trip days (0–3) by intensity × user willingness, at ≤ 1h/day. |
| Caffeine | Counteracts sleepiness but does not shift the clock materially at consumer doses; half-life ~5h; late intake fragments sleep (Drake et al. 2013). | A daily "works for you" window and a hard cutoff 9h (configurable 8–10) before target bed; framed as masking, never as adaptation. |
| Melatonin (optional) | Exogenous melatonin timed in the (biological) afternoon/evening advances phase (melatonin PRC — Lewy et al.; Cochrane review, Herxheimer & Petrie 2002, supports eastward benefit). Contents of OTC products vary; individual response varies. | Opt-in reminders only, on advance days: timed `melatoninAdvanceLeadHours` (5h) before the shifting bedtime. No dose is ever suggested. Disclaimer text embedded in every such action. |
| Short-trip anchoring | Public health guidance (e.g. CDC Yellow Book jet lag chapter) notes trips of ~≤ 2–3 days may not justify full adaptation. | `automatic` strategy anchors to home time for ≤ 2-night stays with ≤ 5h zone change; user can override. |
| Naps | Short naps (≤ ~30 min) relieve sleepiness with limited sleep-inertia and limited pressure loss for the coming night. | Arrival-day nap offered only after short nights, capped at 30 min, ending ≥ 8h before target bed, dodging commitments. |
| Realistic shift rates | Field adaptation averages ~1h/day (advance) to ~1.5h/day (delay); delays are easier than advances (Waterhouse 2007; Sack 2010). | Scheduled rates: advance 1.0 h/day, delay 1.5 h/day (× 1.25 in Maximum mode) — scheduling targets, not promises. |

## 2. The phase model (assumptions, plainly labeled)

The engine tracks one state variable **B**: hours the body clock has shifted from home
baseline (positive = advance). From B and the user's habitual sleep it derives, per night:

- `bed(t) = habitual home bedtime instant − B`
- `wake = bed + habitual sleep duration`
- `CBTmin = wake − cbtMinHoursBeforeWake` where the offset defaults to **2.5h**
  [ASSUMPTION: literature places CBTmin ≈ 2–3h before habitual wake in adults;
  chronotype nudges ±0.25h are a heuristic, not a measurement].

**Reclock never claims to measure circadian phase.** All timing is presented as flexible
windows ("between 10:00 and 12:00"), rounded to 5 minutes, and the arrival-morning
avoid-light window intentionally extends right up to where seek-light opens, absorbing
estimate error in the safe direction.

### Light windows (rules)

Let `buffer = 0.5h`, `halfWindow = 6h` (both configurable):

- **Advance days:** seek bright (preferably outdoor) light in
  `[CBTmin + buffer, CBTmin + halfWindow]`, first ~2h, clipped to waking hours, plausible
  daylight (07:00–20:00 local), post-landing constraints, and commitments. Avoid bright
  light from day start until `CBTmin + buffer` when that span ≥ 45 min (the red-eye
  "sunglasses first" case).
- **Delay days:** seek bright light in the ~3h ending 30 min before the (shifting)
  bedtime; after dark this becomes "keep your evening bright indoors"
  [ASSUMPTION: evening-light-before-shifted-bed is a practical proxy for the delay
  region of the PRC; strong-delay timing near CBTmin is not practically usable].
  For the first 2 days after a delay-direction arrival, avoid bright light for ~2h after
  waking when that window falls in the advance region.
- Direction is evaluated **per night** from the remaining shift, so return legs and
  multi-city phases flip behavior correctly.

### Sleep fitting (rules)

Hard blocks, in priority order: safety/logistics (2.5h pre-departure airport time; no
sleep from boarding−45 min sensitivity through departure+45 min; none within 75 min of
landing; 60 min post-landing), meal services (unless the user opts to skip meals),
commitments flagged `blocksSleep`, the post-landing daytime gate (no "night" sleep after
a 05:00–19:00 local landing — evening bedtime + optional nap instead), the user's
realistic in-flight maximum (and a 2.5h cap for "rarely" sleepers; **zero scheduled
in-flight sleep for "never" sleepers**, who get a quiet-rest block framed as valuable but
optional). If a night's total drops below 5.5h, the window widens ±1.5h around the
blocks and the plan says why.

### Priorities

Impact scores → buckets (must ≥ 80, helpful ≥ 45): night sleep 95/85, arrival-window
light 90 (avoid 82), stay-awake anchor 88, in-flight sleep 92, later light 75/60,
caffeine cutoff 55, nap 50, wind-down 46, switch-clock 46, melatonin 40 (always
"optional" by type), comfort 20–30. Removing every optional action leaves a complete,
usable plan — enforced by tests.

## 3. Adaptive replanning model

Achieved shift = Σ over past nights of (scheduled nightly delta × credit), credit =
1.0 confirmed done / 0.75 unreported / 0.4 reported missed [ASSUMPTION: partial
adaptation under partial compliance; the 0.75 and 0.4 factors are product heuristics
flagged for review]. Sleep debt accumulates from explicit reports (couldn't sleep +2.5h,
still awake +1h; sleeping reduces it), capped at 6h, and gates nap eligibility.
Replanning regenerates only the future; history is preserved verbatim.

## 4. Safety rails (enforced in code and copy)

- No diagnosis, cure, prevention, or guarantee language anywhere.
- No prescription drug mention; no melatonin dosage; melatonin disclaimer on every
  related action: *"Melatonin affects people differently and product contents can vary.
  This is optional general information, not medical advice. Check with a clinician or
  pharmacist if you have questions, take medication, are pregnant, or have a health
  condition."*
- Drowsiness warning in the explanations screen: don't drive or do hazardous things
  sleepy; adjust the plan instead.
- Validator hard-fails plans that contradict themselves, schedule sleep in blocked
  windows, exceed the user's in-flight cap, include caffeine/melatonin against
  preferences, or lack arrival-day guidance.

## 5. Known limitations

- CBTmin is estimated from habitual sleep, not measured; chronotype adjustment is coarse.
- The single-variable phase model ignores partial re-entrainment asymmetries, light
  history, and individual PRC amplitude differences.
- Daylight window (07:00–20:00) ignores latitude/season (no location data by design —
  privacy over precision; a bundled sunrise table is a possible v2 without location
  permission).
- Scheduled shift rates are targets; real adaptation varies by person and season.
- Compliance credits are heuristics; the post-trip survey exists to calibrate them —
  changes ship as protocol version bumps with human review, never silent learning.

## 6. Exact configuration (v1.0 defaults)

All in `PlanEngineConfiguration` (single source of truth; [REVIEW] = wants specialist
sign-off before stronger marketing claims):

| Constant | Value | Note |
| --- | --- | --- |
| cbtMinHoursBeforeWake | 2.5h | [REVIEW] |
| chronotype adjust | early −0.25 / late +0.25 | [REVIEW] |
| advanceRatePerDay / delayRatePerDay | 1.0h / 1.5h | [REVIEW] |
| maximumIntensityRateMultiplier | 1.25 | [REVIEW] |
| preTripRatePerDay | 1.0h | [REVIEW] |
| antidromicThresholdHours | 9h | [REVIEW] |
| preTripDays (easy/balanced/max) | 0 / 2 / 3 ∩ user willingness | explicit per-trip user choice (0–4 days) overrides both |
| anchorMaxNights / anchorMaxShiftHours | 2 / 5h | CDC-style short-trip rule |
| lightBufferFromCBTmin / lightResponsiveHalfWindow | 0.5h / 6h | [REVIEW] |
| seekLightDuration (min) | 2h (0.75h) | |
| daylightWindow | 07:00–20:00 | latitude-naive, see §5 |
| avoidLightDaysAfterArrival | 3 | |
| takeoff / landing sleep buffers | +45 min / −75 min | |
| minimumUsefulInFlightSleep | 1.5h | |
| minimumLayoverForSleep | 5h | |
| practical bedtime clamp | 20:30–01:30 local | [REVIEW] |
| minimumProtectedSleep | 5.5h | |
| maxNapMinutes / napBufferBeforeBed / napSleepDebtThreshold | 30 / 8h / <5h night | [REVIEW] |
| caffeineCutoffHoursBeforeBed / caffeineDelayAfterWake | 9h / 45 min | [REVIEW] |
| melatoninAdvanceLeadHours / melatoninForDelays / melatoninDaysAfterArrival | 5h / off / 3 | [REVIEW] |
| compliance credits done/unknown/missed | 1.0 / 0.75 / 0.4 | [REVIEW] |
| maxActionsPerDay easy/balanced/max | 5 / 8 / 11 | |
| notification caps/day easy/balanced/max | 3 / 5 / 7 | |
| recoveryBufferDays / maxAdaptationDays | 1 / 8 | |

## 7. Sources (non-exhaustive, for the reviewing specialist)

- Khalsa SBS et al. *A phase response curve to single bright light pulses in human
  subjects.* J Physiol 2003.
- Eastman CI, Burgess HJ. *How to travel the world without jet lag.* Sleep Med Clin 2009.
- Waterhouse J et al. *Jet lag: trends and coping strategies.* Lancet 2007.
- Sack RL. *Jet lag.* N Engl J Med 2010.
- Herxheimer A, Petrie KJ. *Melatonin for the prevention and treatment of jet lag.*
  Cochrane 2002.
- Drake C et al. *Caffeine effects on sleep taken 0, 3, or 6 hours before going to bed.*
  J Clin Sleep Med 2013.
- CDC Yellow Book, Jet Lag chapter (current edition at time of writing).

## 8. Version history

| Protocol | Date | Changes |
| --- | --- | --- |
| v1.0 | 2026-07 | Initial protocol as specified above. |

**Review gate:** items tagged [REVIEW] require sign-off from a credentialed sleep /
circadian specialist before marketing language may exceed "general wellness guidance,"
and before any change to defaults ships. Survey-driven tuning proposals must be reviewed
the same way; the engine has no self-modifying behavior.
