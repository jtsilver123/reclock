# Reclock — working agreements

## Git & builds
- **Never `git push` or trigger a TestFlight/CI dispatch until the user explicitly
  says "push."** Commit locally and report that work is committed and waiting.
  This is a standing rule from the owner (2026-07); it survives session restarts.
- Development happens on the designated `claude/…` branch; no PRs unless asked.

## Product philosophy (owner-set)
- Plan preferences live with the plan (Adjust Plan sheet), not scattered in
  Settings. Settings is for app-level concerns: notifications, backup, privacy,
  about — plus a single link into the full preferences editor.
- The Plan tab carries no configuration knobs; the app assumes the right answer
  (per-day zones, everything shown) and announces context passively.
- Simplicity first: one-shot flows (flight code → plan), progressive disclosure,
  "a baby should be able to use it."
- Onboarding asks nothing: welcome → optional sign-in (framed as backup only) →
  straight into flight lookup. The plan assumes a typical sleeper; the Plan-tab
  primer announces the assumptions and the Adjust sheet is the optional step 2.

## Build system facts (hard-won)
- CI's Xcode compiles the FoundationModels stub path; only the TestFlight
  archive (Xcode 26) compiles the real assistant code.
- Secrets reach release builds via `Reclock/Services/InjectedSecrets.swift`,
  overwritten by testflight.yml before archiving (custom INFOPLIST_KEY_
  injection silently drops non-Apple keys). A verify step fails the archive if
  the key is missing from the binary.
- Interactive views nested inside a List row's NavigationLink hijack row taps —
  keep trip rows pure NavigationLink; secondary actions go to swipe actions.
- swiftc -parse on Linux misses type-check errors; the kit is fully testable on
  Linux (`/opt/swift/usr/bin/swift test` in ReclockKit/), app-side truth is CI.
