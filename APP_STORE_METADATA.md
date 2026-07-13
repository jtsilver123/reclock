# APP_STORE_METADATA

## Identity

| Field | Value |
| --- | --- |
| Name | Reclock: Jet Lag Planner |
| Subtitle | Sleep, Light & Caffeine Plan |
| Tagline (marketing) | Feel local when you land. |
| Primary category | Travel |
| Secondary category | Health & Fitness |
| Price | Free (no IAP) |
| Age rating | 4+ (no objectionable content; wellness guidance with clear non-medical framing) |

## Screenshots & icon (generated, ready to upload)

`python3 tools/make_store_assets.py` regenerates everything:

- **Icon** — `Reclock/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png`
  (ships inside the build automatically; nothing to upload).
- **Screenshots** — `store/screenshots/01…06.png`, 1320×2868 (6.9"). App Store
  Connect accepts this single size for every iPhone slot. Upload in numeric order;
  each panel's headline doubles as its caption:
  1. Feel local when you land · 2. Your day, drawn in color · 3. Add a flight in
  seconds · 4. Flight delayed? Plan adapts · 5. Beat jet lag together · 6. Private
  by default.
- **Link preview** — `web/invite/og.png` for the invite page.

## Promotional text (170 chars max)

> Automatically turn your flights into a practical plan for sleep, sunlight, caffeine,
> and arrival-day recovery. Completely free.

## Keywords (100 bytes max — validate before submission)

```
circadian,timezone,body clock,sunlight,melatonin,recovery,international,trip,reminder,flight
```
(93 bytes ASCII — fits. Avoids repeating name/subtitle words: jet, lag, planner, sleep,
light, caffeine, plan.)

## Description

> **Your flights are already there. Your jet lag plan appears automatically.**
>
> Reclock turns any trip into a clear, personal schedule for sleep, bright light,
> caffeine, and recovery — so you feel local when you land, not three days later.
>
> **A plan you can actually follow**
> Built around your real life: your normal sleep, whether you can sleep on planes (be
> honest), meal service, layovers, work meetings, even the wedding on arrival night. No
> 4 p.m. bedtimes, no pretending you'll sleep nine hours in economy.
>
> **Know exactly what to do now**
> One glance shows Now, Next, and Tonight. The full timeline — before departure, in
> flight, after arrival, recovery days, and the trip home — is one tap away, in
> destination time, home time, or both.
>
> **It adapts when travel doesn't cooperate**
> Flight delayed? Slept through the light window? Espresso happened? Tell Reclock and
> the rest of the plan rebuilds from where your body clock actually is, and tells you
> what changed.
>
> **Flights import themselves**
> Reclock finds flights that apps like Flighty and TripIt or airline emails put in your
> calendar — scanned on your device, shown to you for approval. Or type a flight in
> under a minute.
>
> **Why it works**
> Timed light is the strongest signal your body clock has; sleep timing, an honest
> caffeine cutoff, and optional melatonin reminders do the rest. Every step says when,
> and why, in plain language — and short trips get the honest answer: sometimes the best
> plan is staying on home time.
>
> **Private by design**
> Free with no ads, no account, and no server. Your calendar and health data never leave
> your device. Works fully offline once your plan exists — airplane mode included.
>
> Reclock provides general wellness guidance for travelers, not medical advice.

## What's New template

> • [Feature]
> • [Improvement]
> • Planning protocol v[x.y] — see in-app "Why this works" for details
> Fixes and polish. Tell us what felt off after your last trip: the post-trip check-in
> literally shapes the defaults.

## Screenshot sequence (6.9" + 6.5"; capture plan below)

1. **Beat jet lag for free** — Home on landing day, Now card "Get outside into bright
   light" with countdown. *Personalized guidance for every flight.*
2. **Your flights appear automatically** — Calendar import confirmation list.
   *Import from Calendar or enter a flight in seconds.*
3. **Know exactly what to do now** — Now/Next/Tonight composition. *See what matters
   now, next, and tonight.*
4. **A plan you can actually follow** — Timeline "In flight" + arrival day showing
   meal-aware sleep block and capped nap. *Built around your sleep, schedule, and cabin.*
5. **Updates when travel changes** — Delay sheet + change banner ("Sleep moved 2 hours
   later"). *Recalculate after delays, missed sleep, or new plans.*
6. **Feel local when you land** — Progress ring near 100% with "Fully adjusted" quiet
   day. *Follow your progress through the first days of your trip.*

Capture plan: Simulator iPhone 16 Pro Max & 15 Pro Max, dev-menu fixtures
(Helsinki landing day for 1/3/6; LAX→HND for 4; delayed EWR→LHR for 5), light mode
shots 1–5, shot 6 dark mode; status bar cleaned via `xcrun simctl status_bar override`.

## Review notes (App Review box)

> Reclock is a free jet lag planning utility. No account, no server: all features work
> locally. To see a full active-trip experience immediately: launch → "See an example"
> on the first screen loads a demo trip placed on landing day. Calendar access is
> optional (used only to detect flight events, on-device); notifications are optional;
> the app is fully usable when both are denied. Wellness positioning: the app gives
> general schedule suggestions (light/sleep/caffeine timing), never diagnoses or treats;
> melatonin content is optional information with a clear non-medical disclaimer and no
> dosage.

## Support FAQ (reclock.app/support draft)

- **Is it really free?** Yes. No subscription, ads, or unlocks. 
- **Why don't I see my flight after calendar import?** The event may not contain
  recognizable flight details. Add it manually — under a minute — and it merges into
  your trip.
- **I can't sleep on planes.** Tell Reclock exactly that during setup. Plans will use
  quiet-rest blocks and protect your first night instead.
- **My flight was delayed.** Trip → "My flight changed / was delayed" → new times. The
  rest of the plan rebuilds and reminders reschedule.
- **Where's my data?** On your phone. Settings → Export shows you everything; Delete all
  data erases it.
- **Is this medical advice?** No — general wellness guidance. Talk to a clinician about
  sleep disorders, medication, or pregnancy.

## TestFlight

**Description:** Reclock builds practical jet lag plans from your flights — sleep,
light, caffeine, arrival-day recovery — free and on-device. This beta focuses on plan
realism and the adaptive replan flow.

**Feedback prompts:** After your next real trip: (1) Which recommendation was least
realistic? (2) Did the plan recover well after a delay or missed step? (3) At what
moment did you stop following it, and why? (4) How long until you felt normal?

## App icon brief (shipped)

A clock rising like the sun over a dusk horizon — stars above, warm glow below; ivory
ring, 10:09 hands. Communicates "reset your clock at landing" without airplane clichés.
Source: `Reclock/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png`
(regenerate with `python3 tools/make_icon.py`, requires Pillow).

## Claims hygiene

No "medically proven," "clinically validated," "guaranteed," or cure/prevent language
anywhere in metadata or app. Flighty/TripIt are referenced only as sources of calendar
events (true), never as integrations or partnerships.
