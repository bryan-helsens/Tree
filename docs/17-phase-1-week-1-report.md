# 17 — Phase 1, Week 1: what building it changed

Milestone **M1 — a headless 30-day simulation runs in CI and emits a CSV** — is
complete. Four things in the approved architecture turned out to be wrong or
underspecified once the code existed. All four are corrected in the source; this
records what changed and why, so the docs and the code do not silently diverge.

## 1. Dormancy keys off last interaction, not window size

**Spec said:** "Beyond 72 hours of catch-up, apply dormancy."

**Problem:** that makes dormancy a function of *how the elapsed window was
chunked*. Simulating a 100-hour absence in one call gives 72h active + 28h
dormant; simulating it as two 50-hour calls gives 100h active. The composition
property — the thing the entire offline design rests on — fails.

**Correction:** `GameState.lastInteractionAt` is stored, and each 60-second step
asks *"how long has the player been away at this absolute instant?"* Dormancy is
then a per-step function of absolute time and stored state, so it composes
exactly.

`properties_test.dart` has a dedicated case splitting a 12-day window at 1, 24,
71, 72, 73, 100 and 200 hours. It fails under the original formulation.

## 2. Rain was strong enough to override the player

**Spec said:** rain adds `+2.5 %/h` moisture.

**Problem:** applied continuously, a rainy day delivers **+60 moisture** — more
than enough to fill a tree from empty. The balance harness caught it
immediately: under rain, the *carefully tended* tree was pushed to 98% and
overwatered while the *neglected* one drifted into its ideal band. Overwatering
was happening **to** players rather than **because of** them, which inverts the
entire lesson.

**Correction:** two changes.

- Rain falls in **bursts**. `WeatherOracle.rainRateAt` gates rainfall on smooth
  noise over the hour index, so a wet day sees roughly a quarter of its hours
  actually raining, clustered into showers. A rainy day now contributes ~15
  points, which is meaningful — about one and a half waterings — without being
  decisive.
- **Runoff.** Saturated soil sheds water: incoming rain is scaled by
  `1 − saturation`, ramping from 85% to 100% moisture. Weather alone can no
  longer push a tree deep past its band.

`WorldConditions.rainRate` now carries the actual instantaneous rate, so the
rain the renderer draws and the rain the simulation applies are the same number.

## 3. The simulator needed injectable weather

Not a design error, a testability gap. With weather derived solely from the
world seed, no test could isolate "does good care beat bad care" from "was it
raining." `Simulator.weatherOverride` plus `FixedWeatherOracle` pins the sky.
Production leaves it null.

## 4. `grow_domain` uses hand-written immutables, not `freezed`

The data-model sketch specified `freezed`; the dependency table specified **zero
dependencies** for `grow_domain`. Those contradict. The zero-dependency rule
wins — it is the more load-bearing constraint, and it keeps the simulation free
of codegen. Hand-written `copyWith` costs a little typing and buys a package
that builds anywhere with no build step.

`freezed` remains the right call for app-layer state later, where the classes
are wider and codegen earns its keep.

## Also worth recording

- **The Deep Focus bonus is reported separately** from the base nutrient
  conversion (`FocusYield.bonusNutrients`), so the completion screen can
  celebrate it on its own line instead of folding it invisibly into a total.
  This also makes the code match the published reward table exactly.
- **`SimTime` cannot implement `Comparable`** as an extension type over `int`.
  Comparison operators are defined directly instead.

## Balance harness — first real numbers

30 simulated days, five archetypes, **0.87 seconds**, all ship criteria met:

| Archetype | Lv | Health (min) | Growth | Died |
|---|---|---|---|---|
| Daily, 2 sessions | 11 | 100 (95) | 700 | no |
| Weekend only | 6 | 81 (72) | 545 | no |
| Once a week | 3 | 53 (53) | 449 | no |
| 14-day absentee | 8 | 100 (51) | 571 | no |
| **Deliberate overwaterer** | 11 | 43 (22) | **505** | no |

The last row is the result worth having. The overwaterer completes exactly the
same focus sessions as the careful daily player and earns exactly the same XP —
but ends with **505 growth against 700**. Ignoring the band costs 28% of
progress and leaves a permanently unhappy tree, and still never kills it.
"More isn't better" is now a measurable property rather than an intention.

## One tuning question for you

The daily player reaches **`ancient` — the final growth stage — on day 30**, and
level 11. Focus-session growth injection is doing a lot of that work.

Two readings:

- **Fine.** The vertical slice is judged on whether a stranger gets attached to
  a tree in week one, and a visible full arc helps that.
- **Too fast.** It exhausts the MVP's whole content ladder in a month, and the
  spec's own pacing table implies ~37 days at perfect care *without* session
  injection.

I lean toward stretching the late stages (`mature → ancient` from 600h to
~900h) once there is more content to reach for, and leaving it alone for the
slice. It is now a one-line experiment: `stageHours` in `content.json`, then
re-run the harness. **No action needed unless you disagree** — I will not change
pacing without you.
