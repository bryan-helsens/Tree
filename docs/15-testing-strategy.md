# 15 — Testing Strategy

The brief's section 44 asks for genuine self-testing rather than assumed
correctness. Three properties of this architecture make that unusually achievable:
the simulator is pure, the world is a function of state, and time is injected.

## 1. Test pyramid

| Layer | Tool | What it covers |
|---|---|---|
| Unit | `flutter_test` | vitals maths, comfort bands, economy conversions, streak logic |
| **Property** | custom generators | simulation invariants (§2) |
| Golden | `golden_toolkit` | tree renders per stage/health/season, every UI screen at 3 text scales |
| Integration | `integration_test` | full loops on device, kill/restore, permission flows |
| Headless balance | `tools/balance_sim` | 30-day archetype runs (§4) |
| Performance | CI gate | frame time in the busiest scene |
| Manual | scripted playtest | the acceptance criteria that are about feeling |

## 2. Simulation properties (the important ones)

Run over 10,000 randomised seeds, states and window splits:

1. **Composition.** `run(a→c) ≡ run(a→b) then run(b→c)` for all `a<b<c`.
   This is why fixed 60-second steps on an absolute grid were chosen
   ([05 §1](05-simulation.md#1-time-model)), and it is the single most valuable
   test in the suite.
2. **Determinism.** Same `(state, seed, window)` → byte-identical result, always.
3. **Bounds.** No vital ever leaves `[0,100]`; no `NaN` or `Infinity` reachable
   from any input, including adversarial content values.
4. **Monotonicity.** `simTime` never decreases; `growth` never decreases.
5. **Charter C1.** For any state and any elapsed time up to 365 days with **zero**
   player actions, no tree reaches `dead`. This is the design charter compiled
   into an assertion.
6. **Recoverability.** From any reachable state, there exists a sequence of ≤ 5
   affordable actions returning every living tree to `healthy` within 48 h.
7. **Charter C5.** No reachable state has zero available meaningful actions.
8. **Clock safety.** No sequence of wall-clock manipulations yields more reward
   than the same interval of honest time.

## 3. Persistence tests

- **Kill-and-restore fuzzing:** terminate the process at 40 randomised points
  (mid-animation, mid-transaction, mid-focus-session) and assert exact state
  restoration.
- **Migration fixtures:** a committed database per schema version; every
  migration PR ships a test that opens the previous fixture and asserts the
  result. No fixture test, no merge ([10 §7](10-persistence.md#7-migrations)).
- **Corruption drills:** truncate, bit-flip and zero the database, assert the
  backup ladder recovers without data-loss messaging.

## 4. Balance harness

`tools/balance_sim` runs five archetypes for 30 simulated days and emits CSV:

| Archetype | Must be true |
|---|---|
| Daily, 2 sessions | Level ≥ 8, resource surplus, all trees healthy |
| Weekend only | Still gains ≥ 1 level/week, no deaths |
| Once a week | No deaths, everything recoverable in one session |
| 14-day absentee | **Zero deaths**, all trees dormant and recoverable |
| Deliberate overwaterer | Reaches Stressed in < 24 h, recovers in < 24 h, **never Critical from one mistake** |

Any regression in these numbers fails CI, so a balance change cannot be made by
accident.

## 5. Screen-time testing

- Fake `ScreenTimePlatform` implementations for every capability combination —
  including all-false, which must produce a fully playable game (Charter C4).
- Permission-denial paths tested explicitly, since they are the majority case.
- **A CI grep asserting no logging statement exists in any screen-time code
  path**, in any build configuration
  ([07 §5](07-screen-time-integration.md#5-privacy-architecture)).
- Real-device verification on Android that `queryEvents` totals match the system
  Digital Wellbeing figures within tolerance.

## 6. Visual regression

Golden tests for every growth stage × health state × time of day for each
species, at three quality tiers. Procedural rendering makes these cheap to
generate and makes them the only practical way to catch "the Oak got ugly in this
refactor" before a human does.
