# 16 — Apple Family Controls Entitlement Request

**Action owner: the account holder. Submit in week 1, before any iOS
screen-time code exists.**

This is the longest-lead item in the project ([13 R2](13-risks.md#r2--family-controls-entitlement-is-slow-opaque-or-denied)).
Approval is a manual Apple review; 2026 reports range from days to many weeks,
sometimes with no acknowledgement. It costs nothing to ask early.

## What to request

Apply at <https://developer.apple.com/contact/request/family-controls-distribution>
for `com.apple.developer.family-controls`.

Request it for **every target that needs it**, not just the app:

| Target | Needs entitlement | Why |
|---|---|---|
| `Runner` (the app) | Yes | Calls `AuthorizationCenter.requestAuthorization` |
| `GrowDeviceActivityMonitor` | Yes | Receives `eventDidReachThreshold` |
| `GrowDeviceActivityReport` | Yes | Renders the user's own usage view |

Request the **distribution** entitlement, not only development — the
development one does not ship.

## Draft justification

> GROW is a focus and digital-wellbeing app built around timed focus sessions.
> During a session the user chooses to put their phone down; the app rewards
> that time by advancing a slow, calm simulation the user tends between
> sessions.
>
> We request Family Controls for individual (self) authorization only, to
> support two features:
>
> 1. **Session integrity.** A `DeviceActivityMonitor` extension registers a
>    single `DeviceActivityEvent` covering the duration of a focus session the
>    user has explicitly started, with a small usage threshold. If the
>    threshold is reached, the extension records one boolean in a shared App
>    Group so the app can scale the session's reward. The app never reads which
>    applications were used, never reads usage durations, and stores no usage
>    data beyond that single flag.
>
> 2. **Optional app shielding.** With `ManagedSettings`, a user may choose a
>    set of their own apps to shield for the duration of a session they
>    started. Shielding is opt-in, user-configured, and can be ended at any
>    time from the app with a single tap.
>
> All processing is on-device. The app has no backend and transmits no usage
> information of any kind. Authorization is requested only after the user has
> completed at least two focus sessions without it and has read a full-screen
> explanation of what is accessed and why. The app is fully functional if
> authorization is declined; the screen-time features are an optional
> enhancement, not a gate.
>
> We do not request or use `.child` authorization and do not implement any
> parental-control functionality.

## Why this framing

Reviewers are looking for a specific, bounded, user-benefiting use, and for
evidence the developer understands the privacy model. The draft above:

- states **individual authorization only**, which is the lower-risk category;
- describes the *minimum* data flow (one boolean), matching what the code does;
- makes the opt-in sequence and the graceful-degradation path explicit;
- names the App Group mechanism, showing we know the Report extension cannot
  do this and the Monitor extension can.

## While waiting

Nothing blocks. iOS v1 ships **Gentle mode only**; `iosGroundedMode` and
`iosSanctuaryMode` are compile-time-present, flag-off features enabled in a
later release ([07 §7](07-screen-time-integration.md#7-entitlement-and-policy-risk)).

## Google Play, in parallel

Submit an early **internal-testing** build that declares usage access, purely
to smoke out the policy question before the store listing is finalised
([13 R4](13-risks.md#r4--play-store-rejects-usage-access-for-a-game)). The
in-app disclosure flow in [07 §4](07-screen-time-integration.md#4-permission-flow)
is built to Google's stated prominent-disclosure standard.
