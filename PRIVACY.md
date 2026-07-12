# PRIVACY

Privacy is a product feature of Reclock, not a compliance chore. The architecture makes
the promises cheap to keep: **there is no server, no account, and no third-party SDK.**

## Principles (implemented, not aspirational)

- All data lives on-device in one JSON store the user can export or delete in Settings.
- Calendar scanning runs on-device; detected flights are shown for confirmation and only
  confirmed flight fields (airline/number/airports/times/zones) are stored. Titles,
  attendees, notes, and unmatched events are discarded immediately.
- HealthKit (when the capability is enabled): read-only sleep samples, used on-device to
  suggest typical bed/wake times. Never stored beyond the derived suggestion, never
  transmitted.
- Analytics are **off by default**, opt-in, anonymous (random ID reset by toggling), and
  restricted to a closed event set with no free text (see ANALYTICS.md). With the toggle
  off — the default — the app makes **zero network requests**.
- No advertising, no tracking, no sale of data, no fingerprinting. `NSPrivacyTracking =
  false`, tracking domains: none.

## Data inventory & retention

| Data | Where | Retention | Leaves device? |
| --- | --- | --- | --- |
| Sleep profile (bed/wake, chronotype, preferences) | Local JSON store | Until user deletes | Never |
| Trips & flight segments | Local JSON store | Until user deletes | Never |
| Generated plans, completion states | Local JSON store | Until user deletes | Never |
| Fixed commitments (title + times) | Local JSON store | Until user deletes | Never |
| Post-trip survey answers | Local JSON store | Until user deletes | Only numeric ratings, only if analytics opted in |
| Calendar event content | RAM during scan only | Seconds | Never |
| HealthKit sleep samples | RAM during suggestion only | Seconds | Never |
| Anonymous analytics events (opt-in only) | PostHog (if a key is configured) | Provider default | Yes — event name + coarse properties only |
| Flight-number lookups (only in builds with a schedule key, only when the user searches) | Schedule provider (AeroDataBox) | Not stored by app | Yes — flight number + date only; never identity, device data, or other trips. Disabled by Local-only mode. Default builds have no key and send nothing. |

Deleting a trip removes its plan, state, and notifications. **Settings → Delete all
data** wipes the store, quarantine files, and every scheduled notification.

## Permissions

| Permission | When asked | Why | Denied ⇒ |
| --- | --- | --- | --- |
| Calendar (full access) | Only when the user taps "Import from Calendar," after an in-app explanation | Detect flight events on-device | Manual entry path, one tap away |
| Notifications | Only after the first plan exists, from an in-app card | Deliver plan reminders at the right moments | Today tab acts as an in-app checklist; how-to-enable-later text shown |
| HealthKit (read sleep) | Only from onboarding's optional pre-fill, if capability enabled | Suggest typical bed/wake | Manual time pickers (default anyway) |
| Location (when-in-use) | Only when the user taps "Estimate from my location" on the airport-transfer control | One-shot fix → driving ETA to the departure airport via Apple's Maps service; only the resulting minutes value is kept | Preset picker works exactly the same |

**Location specifics:** Reclock never stores or transmits coordinates itself. The single
fix is used in memory to ask Apple's MapKit for a route ETA (Apple's privacy policy
governs that request, as with any Maps-based app). No background location, no
significant-change monitoring, no geofencing. Local-only mode hides the feature.
Under Apple's privacy-label definitions this is not "collection" (nothing leaves the
device to the developer), so the label remains **Data Not Collected**.

No microphone, no camera, no contacts, no photos, no tracking permission.

## App Store privacy label (accurate as shipped)

With default configuration (analytics off, no key present): **"Data Not Collected."**

If the owner later ships opt-in analytics with a key: declare **Product Interaction**
(Analytics) — *not linked to identity, not used for tracking*, collection optional.
Nothing else changes.

## Privacy manifest

`Reclock/PrivacyInfo.xcprivacy`: no tracking, no tracking domains, no collected data
types, no required-reason API categories (the app uses none of the flagged APIs).
There are no third-party SDKs, so there is no third-party disclosure to aggregate.

## User-facing privacy policy (draft for reclock.app/privacy)

> **Reclock Privacy Policy**
>
> Reclock creates jet lag plans on your device. We designed it so that we don't have
> your data: there are no Reclock accounts and no Reclock servers.
>
> **What the app stores** — your sleep preferences, the trips you add, the plans it
> generates, and your check-in answers. All of it stays in the app's storage on your
> device (and your device backups). Export it or erase it any time in Settings.
>
> **Calendar** — if you choose calendar import, Reclock scans events on your device to
> find flights, shows you what it found, and saves only the flight details you confirm.
> Your calendar's contents are never uploaded.
>
> **Health** — if you choose the sleep pre-fill, Reclock reads recent sleep sessions on
> your device to suggest your typical times. Health data is never uploaded and is not
> used for anything else.
>
> **Location** — only if you tap "Estimate from my location" when setting your airport
> transfer time. Your position is used once to ask Apple Maps for a drive-time estimate
> and is never stored; only the minutes value you confirm is saved.
>
> **Analytics** — off unless you turn them on. If you do, we receive anonymous counts of
> feature usage (e.g. "a plan was generated for a 7-hour eastward trip") under a random
> identifier that resets when you toggle analytics off. Never your calendar, health
> data, flight numbers, notes, or anything typed.
>
> **Notifications** — reminders are scheduled locally on your device.
>
> **Children** — Reclock is a general-audience travel utility (rated 4+) and collects no
> data from anyone.
>
> **Changes** — material changes to this policy ship with an app update and are listed
> in the version notes.
>
> Contact: privacy@reclock.app

## URLs (working placeholders to publish before submission)

- Privacy policy: `https://reclock.app/privacy`
- Support: `https://reclock.app/support`
- Terms: `https://reclock.app/terms`

## Account deletion

Not applicable — no accounts exist. The equivalent user right is **Delete all data**,
which is local, immediate, and complete.
