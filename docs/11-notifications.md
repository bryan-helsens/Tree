# 11 — Notification Strategy

A game about using your phone less that pushes notifications is a contradiction.
This section is written as a set of restrictions first and features second.

## 1. Hard limits

- **Maximum 2 notifications per day**, all types combined.
- **Maximum 1 "care" nudge per day.**
- **Quiet hours 21:30–08:30 local**, user-editable, on by default.
- **Adaptive budget:** after 3 consecutive ignored notifications the daily cap
  drops to 1; after 6, care nudges stop entirely until the player next opens the
  app. The game notices being ignored and gets quieter, not louder.
- **No badge counts.** Ever. A red number is an anxiety generator.
- **No streak-loss warnings.** The Streak Shield covers the miss silently and the
  player is told afterwards ([06 §8](06-economy-and-progression.md#8-streaks)).

## 2. Channels

| Channel (Android) | Importance | Content | Default |
|---|---|---|---|
| `focus` | HIGH | session complete | on |
| `care` | LOW | a tree is drifting out of its band | on |
| `discovery` | DEFAULT | something appeared while you were away | on |
| `daily` | LOW | challenges refreshed | **off** |

Each is independently toggleable in Settings, and Android's per-channel controls
are left intact rather than shadowed by in-app settings.

## 3. Predictive care nudges

The interesting one. On `AppLifecycleState.paused`, we already have a
deterministic simulator and a known future weather sequence, so we can project
forward and schedule precisely:

```dart
final projection = Simulator.project(
  state: state, content: content,
  horizon: const Duration(hours: 72),
  weather: WeatherOracle.forWindow(state.worldSeed, from, to),
);

final firstConcern = projection.firstMomentWhere(
  (t) => t.anyTreeExits(HealthState.healthy) || t.anyTreeBelowWaterBand(),
);
```

That moment is then:
- shifted out of quiet hours to the next friendly slot,
- jittered ±25 minutes so it never feels like a machine,
- **suppressed entirely if it lands within 4 hours of the player's typical open
  time** (a rolling median of session start times) — if they are about to open the
  app anyway, do not interrupt them,
- rescheduled from scratch on every pause, so it is never stale.

Because rain is deterministic, the projection also knows when rain will *fix* the
problem, and will not send a nudge that the weather is about to make wrong.

## 4. Copy rules

A banned-word list is a compile-time constant with a unit test asserting no
notification template contains any of:

> *losing, lost, dying, died, dead, failed, failing, missed, neglect, don't
> forget, hurry, urgent, last chance, running out, streak lost, come back*

Approved voice — observational, present tense, low stakes, one emoji maximum:

- "Your Birch is getting thirsty 💧"
- "Rain came through the forest last night."
- "Your focus session is complete. The forest grew."
- "Something new is moving in the branches 🦋"
- "Your shield covered yesterday 🛡️"

Never a countdown, never a consequence, never a number of days.

## 5. Focus session timing

The session-end notification must be *precise* — a focus timer that fires four
minutes late is broken.

**Android.** `AlarmManager.setAlarmClock()`. This is exempt from Doze, requires
no `SCHEDULE_EXACT_ALARM` grant, and is semantically honest: the user set a timer,
so it is an alarm. The cost is a system status chip, which for a focus timer is a
feature. **We do not use a foreground service** — Android 14+ requires a declared
foreground service type, and no legitimate type fits a timer that is not doing
work. `specialUse` would need a Play Console justification for a service that does
nothing. `AlarmManager` avoids the entire problem.

**iOS.** `UNTimeIntervalNotificationTrigger`, which is exact, plus an optional
**Live Activity** (ActivityKit) showing the countdown on the Lock Screen and
Dynamic Island so the phone can stay face down.

Both platforms: the reward is computed on resume from the trusted clock, not from
the notification. The notification is an announcement, never the source of truth.

## 6. Permissions

`POST_NOTIFICATIONS` (Android 13+) and `UNUserNotificationCenter` authorization
are requested **contextually**, immediately after the player starts their first
focus session — the one moment where the value is self-evident ("we'll tell you
when it's done"). Never at launch. Denial is silent and permanent; a single entry
remains in Settings.

## 7. Offline discovery notifications

When the projection shows a discovery will occur (an animal visit, a stage-up,
a flowering), we schedule **one** gentle notification for it — but only if the
player has not opened the app in over 18 hours, and only within the daily budget.
The point is to reward absence, not to manufacture a reason to return.
