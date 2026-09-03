# 22 — Focus session architecture

The state machine, its persistence, and its relationship to the clock and the
simulation. This document answers twelve questions explicitly, in order.

Implementation: `packages/grow_sim/lib/src/focus_machine.dart`,
`packages/grow_sim/lib/src/clock_guard.dart`,
`packages/grow_domain/lib/src/player/focus_session.dart`,
`packages/grow_data/`.
Tests: `focus_machine_test.dart`, `clock_guard_test.dart`,
`grow_data/test/persistence_test.dart`, `grow_app/test/session_recovery_test.dart`.

---

## 0. The one idea the rest follows from

**A session is a record in the save, not a process.** It has a start time, a
planned length, and a phase. Nothing about it runs. There is no timer, no
callback, no scheduled task, no background service.

Everything below is a consequence. Backgrounding, process death, reboots and
clock tampering are not four features; they are four situations in which the
same comparison — *has `simTime` passed `startedAt + planned`?* — is evaluated
again, on the next launch, and reaches the right answer without having been
running in between.

---

## 1. What are the valid session states?

`FocusPhase`, in `grow_domain`:

| Phase | Meaning |
| --- | --- |
| `running` | Started, planned end not yet reached. |
| `completed` | The planned time has elapsed. Reward is owed, not yet paid. |
| `abandoned` | The player stopped early. Reward is owed *pro rata*, not yet paid. |
| `claimed` | Reward committed. The record survives only so the player can be told. |

Plus the absent state: `GameState.session == null`, "no session".

Two derived predicates carry the meaning so no caller re-derives it:

- `isFinished` — `completed`, `abandoned` or `claimed`.
- `awaitsReward` — `completed` or `abandoned`. This is the *only* thing
  `claim()` acts on.

`abandoned` is deliberately not a failure state. Ending early is a legitimate
outcome of a product about putting the phone down: the time already spent was
real, and it is paid for (Design Charter C2). Nothing in the game punishes it.

## 2. What transitions are allowed?

```
  (none) ──start──▶ running ──elapsed──▶ completed ──claim──▶ claimed ──dismiss──▶ (none)
                       │                                          ▲
                       └────────endEarly──▶ abandoned ──claim─────┘
```

That is the complete set. Every other pair is refused, with a reason:

| Attempt | Refusal |
| --- | --- |
| `start` while one is running | `alreadyRunning` |
| `start` while one is `claimed` | `awaitingAcknowledgement` |
| `start` shorter than the minimum | `tooShort` |
| `start` longer than the maximum | `tooLong` |
| `endEarly` with nothing running | `nothingRunning` |
| `claim` with nothing owed | `nothingToClaim` |
| `dismiss` anything but `claimed` | `nothingToClaim` |

`awaitingAcknowledgement` exists because of what it protects. Overwriting a
claimed session would not lose the reward — that is already committed to the
save — but it *would* lose the moment: the player never sees what their last
session did. The moment is the product.

`claim` on an already-`claimed` session is not in the table because it is not a
transition. It is a no-op that returns the recorded outcome (§8).

## 3. What happens when the app is backgrounded?

Nothing to the session, which is the point.

`GameController.onPaused()` re-anchors the clock (`ClockGuard.anchor`) and
writes the save. That write is the most important one in the app: its
timestamps are what the next resume reasons about.

The session is untouched. It was a record before backgrounding and it is the
same record after. A session that spans backgrounding is not a special case —
it is the ordinary case, and the one the product is *for*. The player is
supposed to put the phone away.

## 4. What happens if the process is killed?

The next launch runs `GameController.resume()`, which is the same code path as
an ordinary launch. There is no separate crash-recovery path, because a launch
after a crash differs only in what the save happens to contain.

`resume()` loads, credits trusted elapsed time, runs the simulator forward,
then settles the session — `evaluate()` to see whether it finished, `claim()`
to commit any reward. A session that completed while the process was dead
completes on the next launch, at its planned end time (§7), and pays exactly
once.

If the process died *between* the reward and the record of it — the classic
double-pay window — there is nothing to recover, because that window does not
exist (§8).

## 5. What happens if the phone restarts?

The monotonic clock resets, so the guard cannot use it. `ClockReading` carries
a `bootId`; when it differs from the one in the save, `ClockGuard` falls back to
the wall clock **capped at `maxResumeMs` (36 hours)**.

So a reboot credits real elapsed time up to a day and a half, and no more. The
cap is what stops "reboot with the clock wound forward" from being a growth
exploit, and 36 hours is generous enough that an honest player who leaves the
phone off over a long weekend loses nothing they would notice.

A session in progress across a reboot completes normally, subject to that cap.

## 6. What happens on interruption?

Two different things are called interruption, and they are not the same:

- **The player stops.** `endEarly()` → `abandoned`, paid pro rata. A choice,
  not a failure.
- **The phone is picked up / the app is left.** This is *not* a state
  transition, and by design never will be. It is a *measurement* that scales
  the reward: `FocusEconomy.integrityFrom(window:, screenOn:)` maps screen-on
  time during the session to a multiplier floored at 0.35, with 4% grace so
  glancing at the clock costs nothing. Breaking focus costs yield; it does not
  cancel a session. A state machine that punishes a glance at a notification is
  one that makes people anxious about their phone — the opposite of the product.

Nothing else interrupts a session. There is **no failure phase**, at any
integrity (Design Charter C2).

**Not yet wired.** `integrityFrom` exists and is tested, but `claim()` currently
calls `yieldFor` with the default `integrity: 1.0`, because the platform
screen-time source is not connected in the vertical slice — that is the Family
Controls / Usage Access work in [docs/07](07-screen-time-integration.md), gated
on the Apple entitlement in [docs/16](16-apple-entitlement-request.md). The
state machine has nowhere else to change when it lands: integrity is an argument
to a yield calculation, not a phase.

## 7. How is completion determined?

By a comparison, not a callback:

```dart
session.hasElapsedAt(state.simTime)   // simTime.ms - startedAt.ms >= planned
```

`FocusMachine.evaluate()` runs this after every simulation advance — the
foreground tick and the launch catch-up alike — and moves `running` to
`completed`.

The completion is stamped at **`startedAt + planned`**, not at the moment it was
noticed. A session that finished four hours ago while the app was closed
finished four hours ago. This matters for two reasons: the reward is computed
against the day the session actually ended (day rollover, fatigue, streaks), and
the world has already lived through the session by the time the reward lands
(§12).

## 8. How is the reward committed exactly once?

**By construction, not by locking.** The reward and the move to `claimed` are
fields of the same `GameState`:

```dart
final next = rewarded.copyWith(progression: …).withSession(
  session.copyWith(phase: FocusPhase.claimed, outcome: outcome),
);
```

`GameState` is immutable and is written to disk whole. So there is no instant at
which the reward has been applied and the phase has not. A crash either loses
both — and the session is still `completed`, and claims on the next launch — or
keeps both, and the `claimed` phase refuses a second attempt. There is no third
outcome and therefore no window to defend.

This is also why the reward is **never gated on the player tapping anything**.
`resume()` claims automatically. The completion screen shows what has already
been committed; it does not commit it. A reward that requires acknowledgement is
a reward that can be lost by closing the app.

## 9. How are duplicate rewards prevented?

Three independent mechanisms, in order of what they catch:

1. **The phase.** `claim()` acts only on `awaitsReward`. A `claimed` session
   returns its recorded `SessionOutcome` unchanged — idempotent, so a retry
   after an ambiguous failure is safe rather than expensive.
2. **The single-write atomicity of §8.** No partial commit exists to replay.
3. **The `simTimeHighMs` watermark in `ClockMeta`.** Simulated time never moves
   backwards, even if an older save is restored from a backup. Restoring a save
   from before a session cannot re-earn that session's time.

`session_recovery_test.dart` relaunches ten times against a save containing a
finished session and asserts a single payment.

## 10. How does this interact with the fixed 60-second simulation grid?

It does not perturb it, which is the requirement.

The simulator advances in 60-second steps on an absolute grid, giving the
composition property `run(a→c) ≡ run(a→b) then run(b→c)`. Sessions do not
schedule steps, do not add steps, and do not shift the grid.

A session's boundaries are *read against* `simTime`, not written into it:

- `evaluate()` is a pure comparison performed after an advance.
- Completion is stamped at `startedAt + planned` — an exact millisecond, which
  need not fall on a step boundary and does not have to.

So the session's resolution is exact while the world's remains one minute. The
only visible consequence is that a session can be recognised as finished up to
59 seconds after its true end, and it is still credited at its true end.

## 11. What happens if the clock moves unexpectedly?

`ClockGuard` credits `min(Δwall, Δmonotonic)` within a boot, so winding the
device clock forward credits nothing extra: the monotonic clock did not move,
so the minimum did not either.

| Situation | Detected as | Credited |
| --- | --- | --- |
| Wall clock rewound | `rewind` | Zero. Never negative time. |
| Wall ≫ monotonic within a boot | `forwardJump` | The monotonic delta. |
| Different `bootId` | `reboot` | Wall delta, capped at 36 h. |
| First run of a save | — | Zero, and the anchor is persisted. |
| Normal | `none` | The elapsed interval. |

Two details that cost real bugs:

- **The fresh-clock anchor must be persisted.** Recording it in memory only
  means every launch finds a fresh clock again and no offline time is *ever*
  credited. `resume()` awaits that write.
- **Anomalies are recorded, not punished.** `ClockMeta.anomalies` counts them.
  A player whose phone changed time zone is not a cheat, and nothing in the game
  accuses them.

Winding the clock forward therefore cannot finish a session. There is a test
that tries.

## 12. How does completion feed the domain and simulation pipeline?

The required invariant, implemented with no shortcut anywhere:

```
session completion → domain reward → simulation consequence
                  → WorldSnapshot/FoliageState → visual response
```

Concretely, inside `resume()` / `_settle()`:

1. `Simulator.run()` advances the world to the trusted present. **The session's
   own duration is simulated** — the tree got thirsty while you were away.
2. `evaluate()` marks the session `completed` at its true end.
3. `claim()` computes the yield and produces one new `GameState` carrying the
   resources, XP, streak, daily stats, growth and the `claimed` phase.
4. `WorldProjector.project()` derives a new `WorldSnapshot` and `FoliageState`.
5. The renderer reacts to that state.

**The focus UI cannot grow the tree.** `GameController` is the only mutation
entry point, it exposes no appearance state, and the growth injection is applied
in `grow_sim` via `addGrowth`. The completion screen reads
`SessionOutcome`; it has nothing to write with. `session_recovery_test.dart`
asserts this directly ("the focus flow never touches the tree directly").

### Growth is applied in one place

`addGrowth` (`grow_sim/src/growth.dart`) is the single path for adding growth,
used by both the simulator's hourly accrual and the session reward. They had
drifted: the reward path added points to a clamped `Vital`, so a session that
should have finished a stage silently lost everything above 100, and a session
awarded to a fully grown tree reported growth that never happened.

Overflow is carried across stage boundaries **through hours, not raw
percentages**, because growth is stored as a percentage of the current stage and
stages are not the same length — spilling four hours' worth of the 4-hour Sprout
stage into the 24-hour Seedling stage would invent progress.

`SessionOutcome.growthInjection` records what actually landed, which is zero for
an Ancient tree. A completion screen must not promise growth the player can see
did not happen.

---

## Persistence

`packages/grow_data` owns the save and depends only on `grow_domain`.

- **`SaveCodec`** — the whole `GameState` to and from JSON, `schemaVersion 1`.
  A save from a *newer* schema raises `SaveVersionError` rather than being
  partially parsed; downgrade is a data-loss event and is refused loudly.
- **`GuardedSaveRepository`** — serialises writes through a single-writer queue,
  so two overlapping saves cannot interleave, and keeps rotating backups. A
  corrupt load falls back to the most recent good backup.
- **Session mutations await their write.** `startSession`, `endSessionEarly`
  and `dismissSession` return `Future` and await persistence. Fire-and-forget
  leaves a window in which the session exists in memory but not on disk; a
  process death inside that window loses a session the player has already
  begun. This was a real bug, caught by relaunch tests.

`GameState.withSession()` is deliberately separate from `copyWith`. A `null`
session is meaningful — it means "no session" — and `copyWith` cannot express
"set this to null" without ambiguity. Making the session an explicit call also
means every place that clears a session is greppable.
