# 07 — Screen Time Integration

This is the hardest technical section in the project and the one most likely to
be quietly faked. It is not faked here.

## 1. The honest capability matrix

| Capability | Android | iOS |
|---|---|---|
| Total screen-on minutes per day | ✅ `UsageStatsManager.queryEvents` → `SCREEN_INTERACTIVE` / `SCREEN_NON_INTERACTIVE` | ❌ **Impossible** |
| Per-app usage totals | ✅ available — **we deliberately do not request or read it** | ❌ Impossible outside the report extension |
| Retroactive query of a past window | ✅ | ❌ |
| Usage threshold callback | ✅ (we derive it ourselves) | ✅ `DeviceActivityMonitor.eventDidReachThreshold` |
| Show the user their own usage chart | ✅ we can compute it | ⚠️ only rendered *inside* `DeviceActivityReport`; the app can never read the numbers |
| Block apps during a session | ⚠️ only via AccessibilityService — **policy-hostile, we will not** | ✅ `ManagedSettingsStore.shield` |
| Works with zero permissions | ✅ | ✅ |

The two platforms are **not symmetric and cannot be made symmetric.** The
architecture treats iOS parity as impossible and designs around it rather than
pretending.

### Why iOS cannot report usage numbers

Apple's `DeviceActivityReportExtension` runs in a sandbox that cannot make
network requests and cannot write to shared containers — App Group `UserDefaults`
and shared files both silently fail to reach the host app. Apple staff have
stated on the developer forums that moving Device Activity data outside the
extension is not possible, by design, to preserve user privacy. The extension can
only emit SwiftUI views.

So on iOS the app can *show* a person their screen time inside a view it does not
control, and can never *know* it. Any product that claims otherwise on iOS is
either using thresholds (as we do below) or is not doing what it says.

## 2. Three modes, chosen by the player

### Gentle — default, zero permissions, both platforms

Honour mode. The session runs; app lifecycle is observed (`AppLifecycleState`,
`didEnterBackground`); the reward is granted at **full integrity (1.0)**.

Full, not reduced. Cheating a game with no leaderboard cheats nobody, and
withholding reward from the 90% of players who will never grant a special
permission would make the default experience the punished one — the opposite of
[Charter C4](00-design-charter.md#c4--the-game-is-fully-playable-with-zero-permissions-granted).

Optional and off by default: a **Live Activity** (iOS) / ongoing notification
(Android) showing the session timer on the lock screen, so the phone can be face
down and still tell you how long is left without unlocking it.

### Grounded — opt-in, permission required

**Android.** After the session ends, the app makes a single retroactive query:

```kotlin
val events = usageStatsManager.queryEvents(sessionStartMs, sessionEndMs)
// count only SCREEN_INTERACTIVE / SCREEN_NON_INTERACTIVE transitions
// → total screen-on milliseconds within the window
// no package names are read, stored, or resolved
```

No background service. No polling. No wakelock. **Zero battery cost while the
session runs**, because nothing runs. This is a direct benefit of the retroactive
model and one of the better properties of the whole design.

Integrity is then a smooth curve, never a pass/fail:

```
usedFraction = screenOnMs / windowMs
integrity    = clamp(1.0 - 1.3 · max(0, usedFraction - 0.04), 0.35, 1.0)
```

The 4% grace means glancing at the time costs nothing. Using the phone for half
the window still returns 0.35 — reduced, never zero, never "failed."

**iOS.** `FamilyControls` individual authorization + a `DeviceActivityMonitor`
extension with a `DeviceActivityEvent` whose threshold is a small allowance
(e.g. 3 minutes) over the session's schedule. If `eventDidReachThreshold` fires,
the extension writes a flag to App Group `UserDefaults` — the *monitor* extension
can do this, unlike the *report* extension — and the host app reads one boolean
on resume. Integrity becomes `1.0` or `0.6`. Coarse, but honest and real.

> The monitor extension has a **6 MB memory budget**. It writes one boolean and
> nothing else. Any temptation to do work there must be resisted.

### Sanctuary — iOS only, opt-in

With Family Controls granted, `ManagedSettingsStore.shield.applications` blocks a
player-chosen app set for the session's duration. One tap to end early, always,
with no penalty beyond the pro-rated reward. This is the only *enforcement* the
product ships, it is opt-in twice (permission + mode), and it is user-configured.

Android has no equivalent that does not abuse `AccessibilityService`. Google Play
restricts Accessibility APIs to accessibility purposes, and using them to block
apps risks removal. **We will not ship it.** This asymmetry is stated in the UI,
not hidden.

## 3. Baseline comparison ("you're using your phone 18% less")

**Android only.** Rolling 14-day median of daily screen-on minutes, computed
entirely on device.

```
reduction = clamp((baselineMedian − today) / baselineMedian, 0, 0.30)
bonusGP   = round(reduction · 400)          // capped at 120 GP/day
```

- GROW's own foreground time is **excluded** from both sides, and the UI says so.
- Median, not mean, so one unusual day does not distort the baseline.
- Requires 7 days of data before the feature appears at all.
- Never phrased as a comparison to other people, and never shown as a raw hourly
  total unless the player opens the optional detail view.

**iOS gets the one-bit variant.** The player sets a daily goal (e.g. 3 hours). A
`DeviceActivityEvent` with that threshold either fires or does not. Absence of the
event by end of day means the goal was met.

That is genuinely all we can learn — **one bit per day** — and it is sufficient
for the reward. It is also, arguably, the correct amount of information for an app
like this to have about a person. We frame it that way in the UI rather than
apologising for it.

## 4. Permission flow

Nothing is requested at launch. The sequence, per Google Play's prominent
disclosure requirements:

1. The player completes at least two focus sessions in Gentle mode.
2. A card appears in the Focus tab: *"Want your forest to notice when you put
   your phone down?"*
3. Tapping it opens a **full-screen explanation before any system dialog**:
   - what is read (total screen-on time only),
   - what is never read (which apps, what you do, any content),
   - where it is stored (this device, 14 days, deleted after),
   - what it is used for (a bonus, nothing else),
   - that everything works without it.
4. Only then: `Settings.ACTION_USAGE_ACCESS_SETTINGS` (Android) or
   `AuthorizationCenter.shared.requestAuthorization(for: .individual)` (iOS).
5. Denial is a non-event. No re-prompt, no nag, no reduced rewards. A single
   entry stays in Settings for later.

## 5. Privacy architecture

- **No network.** The MVP ships with no analytics SDK and no backend. Screen-time
  data physically cannot leave the device because there is nothing to send it to.
- **The schema cannot hold app identities.** `ScreenTimeDay` has two integers and
  a boolean ([04 §4](04-data-models.md#4-screen-time-model)). This is a structural
  guarantee, not a policy promise.
- **`QUERY_ALL_PACKAGES` is not declared** and no `<queries>` element for package
  visibility is needed, because we never resolve a package name.
- **14-day retention**, hard-deleted by a DAO that runs on every launch.
- **Logging ban:** a CI test greps plugin sources for log statements in
  screen-time code paths and fails the build.
- One-tap **"Delete my screen-time data"** in Settings, which also revokes and
  clears the baseline.
- Data safety declarations on both stores will state: screen time is *accessed*,
  not *collected* and not *shared* — which will be true.

## 6. Plugin contract

```dart
abstract class ScreenTimePlatform {
  Future<ScreenTimeCapabilities> capabilities();
  Future<AuthorizationStatus> status();
  Future<AuthorizationStatus> requestAuthorization();

  /// Retroactive integrity for a completed window.
  /// Returns null when unavailable — callers MUST treat null as integrity 1.0.
  Future<SessionIntegrity?> integrityFor(DateTimeRange window);

  /// Aggregate screen-on minutes per day. Android only; empty elsewhere.
  Future<List<ScreenTimeDay>> dailyTotals({required int days});

  /// iOS only: register / clear the daily-goal threshold event.
  Future<void> setDailyGoal(Duration? goal);

  /// Sanctuary mode. iOS only; no-op elsewhere.
  Future<void> beginShield(ShieldSelection s);
  Future<void> endShield();

  Future<void> deleteAllData();
}

@freezed
class ScreenTimeCapabilities with _$ScreenTimeCapabilities {
  const factory ScreenTimeCapabilities({
    required bool canMeasureAggregateUsage,   // Android + permission
    required bool canDetectThresholdOnly,     // iOS + entitlement
    required bool canShieldApps,              // iOS + entitlement
    required bool canCompareToBaseline,       // Android only
  }) = _ScreenTimeCapabilities;
}
```

Every UI surface is driven by `capabilities()`. **No feature is ever shown on a
platform that cannot deliver it**, and no code path assumes a capability exists.

## 7. Entitlement and policy risk

**Family Controls is the longest lead item in the whole project.**

- The `com.apple.developer.family-controls` entitlement requires a manual request
  to Apple with a written justification, and **every target needs it separately** —
  the app *and* each extension. Approval has been reported at anywhere from days
  to many weeks, sometimes with no acknowledgement at all.
- **Action: submit the request in week 1 of Phase 1**, before any iOS screen-time
  code exists, framed as a focus/wellbeing tool. It is free to ask early and
  expensive to ask late.
- **Contingency:** iOS v1 ships **Gentle mode only**. `iosGroundedMode` and
  `iosSanctuaryMode` are compile-time-present, flag-off features that turn on in a
  later release. No launch date depends on Apple's queue.

**Google Play** requires prominent in-app disclosure before requesting usage
access, and the permission must serve a core, disclosed feature. Our flow (§4)
is built to that standard. Residual risk: a reviewer decides a *game* has no
legitimate need for usage access. **Contingency:** the feature is a bonus tier,
so it can be removed in a patch without touching the core loop — which is exactly
why the architecture keeps it behind a capability flag rather than in the
critical path.

---

**Sources consulted for this section**

- [Requesting the Family Controls entitlement — Apple Developer Documentation](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement)
- [DeviceActivityReportExtension — Apple Developer Documentation](https://developer.apple.com/documentation/deviceactivity/deviceactivityreportextension)
- [Is Screen Time trapped inside DeviceActivityReport on purpose? — Apple Developer Forums](https://developer.apple.com/forums/thread/817516)
- [Send device activity data to external server — Apple Developer Forums](https://developer.apple.com/forums/thread/727958)
- [Device Activity monitor extension — Apple Developer Forums](https://developer.apple.com/forums/thread/805859)
- [Family Controls entitlement request submitted March 2026, no response — Apple Developer Forums](https://developer.apple.com/forums/thread/818553)
- [Permissions and APIs that Access Sensitive Information — Play Console Help](https://support.google.com/googleplay/android-developer/answer/16558241?hl=en)
- [Best practices for prominent disclosure and consent — Play Console Help](https://support.google.com/googleplay/android-developer/answer/11150561?hl=en)
