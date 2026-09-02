# 05 — Simulation

Every constant below is a starting value to be tuned with `tools/balance_sim`,
not a final number. What matters is the *shape* of each curve, because the shapes
encode the design intent.

## 1. Time model

**Fixed 60-second steps on a global grid, always.** No adaptive step size.

```dart
int stepIndex(SimTime t) => t.ms ~/ 60000;   // absolute, not relative to start
```

Aligning steps to an absolute grid buys the single most valuable property in the
system:

> `run(a → c)` produces the same state as `run(a → b)` followed by `run(b → c)`.

That is a property test ([15 §2](15-testing-strategy.md)), and it is why a player
who opens the app twice gets the same forest as one who opens it once.

**Cost check.** 72 hours = 4,320 steps. Per step per tree: 4 `band()` evaluations
(~6 `pow` calls), plus growth, health and event rolls — call it 200 float ops.
Five trees → ~4.3M ops → roughly 15–40 ms AOT on a mid-range phone. Well within
budget for a screen that is playing a "while you were away" animation anyway. It
runs in an isolate regardless.

**Cap:** `MAX_ACTIVE_CATCHUP = 72 h`. Beyond that, dormancy (§7).

## 2. Comfort bands

The heart of the over/under-watering design. One function, used for all four
vitals.

```
band(x, lo, hi, tolLo, tolHi):
    if lo ≤ x ≤ hi:  return 1.0
    if x < lo:       d = (lo - x) / tolLo
    else:            d = (x - hi) / tolHi
    return clamp(1 - d^1.35, 0, 1)
```

The exponent 1.35 makes the penalty **gentle just outside the band and steep
further out**. Drifting to 5% below ideal costs almost nothing; sitting 25% above
it is genuinely bad. That is what teaches "close enough is fine, but more is not
better" without a tutorial.

Tolerances are asymmetric, because plants are:

| Vital | tolLow | tolHigh | Rationale |
|---|---|---|---|
| Water | 30 | **20** | Roots suffocate faster than leaves wilt |
| Nutrition | 35 | **18** | Nutrient burn is the harshest common mistake |
| Light | 25 | 25 | Symmetric |
| Temperature | 12 | 12 | Symmetric, species-specific bands |

**Composite comfort** — a weighted geometric mean, so one badly wrong vital
dominates rather than being averaged away:

```
C = ( Cw^1.5 · Cn^1.0 · Cl^0.8 · Ct^0.6 ) ^ (1 / 3.9)
```

## 3. Water

```
dW/dt = rain(t) + irrigation - consumption

consumption = K_W · sp.waterUse · stageDrink[stage] · evapo(weather, timeOfDay)
              · (0.5 + 0.5·W/100)          ← wet soil dries faster
              · soilRetention(slot)

K_W          = 1.15 %/h
stageDrink   = [0.30, 0.50, 0.65, 0.80, 1.00, 1.30, 1.50]
evapo        = sunny 1.25 · cloudy 1.00 · rain 0.60 · storm 0.70 · fog 0.75 · snow 0.50
               × 0.70 at night
soilRetention= loam 1.00 · sandy 1.25 · clay 0.80 · mulched 0.85
```

The `(0.5 + 0.5·W/100)` term is important: drying is proportional to wetness, so
moisture decays **asymptotically toward a floor instead of hitting zero**. A tree
left alone gets thirsty and then stays thirsty; it does not desiccate to 0% and
sit there taking maximum damage.

*Worked example.* Young Oak, `waterUse = 1.0`, loam, average weather
`evapo ≈ 1.05`, at `W = 60`:
`consumption = 1.15 × 1.0 × 1.0 × 1.05 × 0.8 × 1.0 = 0.97 %/h` ≈ **23%/day**.
One Water unit gives `+11 × sp.absorption`, so an Oak needs roughly **two
waterings a day** — one focus session's worth. That is the intended tension.

## 4. Nutrition

```
dN/dt = -( K_N · sp.nutrientUse · growthPotential ) - leach(W)

K_N   = 0.55 %/h
leach = W > 85 ? 0.03·(W - 85) : 0
```

Two deliberate couplings:

1. **Uptake scales with actual growth.** A stalled or dormant tree barely
   consumes nutrients, so neglect does not compound into a second failing vital.
2. **Overwatering leaches nutrients.** Systemic, real, and it means over-caring
   in one dimension visibly costs you in another — the strategic lesson the brief
   asks for, expressed as physics rather than as a popup.

## 5. Growth

```
dG/dt = (100 / stageHours[stage] / sp.growthRate)
        · C^1.6
        · healthGate(H)
        · seasonModifier
        · lightHoursFactor

healthGate(H) = clamp((H - 25) / 45, 0, 1)     // nothing grows below 25 health
```

`C^1.6` means excellent care grows a tree roughly **2.1× faster** than mediocre
care (C=1.0 vs C=0.75), which is a big enough gap to make optimisation feel worth
it and small enough that a casual player still progresses.

Growth **never reverses**. Damage costs time, not progress. This is a direct
consequence of Charter C1.

Target pacing at perfect care (`stageHours` for the starter Oak):

| Transition | Hours | Feels like |
|---|---|---|
| seed → sprout | 0.33 | one focus session — the first payoff |
| sprout → seedling | 4 | same evening |
| seedling → sapling | 24 | day two |
| sapling → young | 72 | day four |
| young → mature | 192 | week two |
| mature → ancient | 600 | week five |

**Focus sessions inject growth directly:** `ΔG = growthPoints × 0.02` percent of
the current stage. A 30-minute session moves a stage-3 tree by ~3% instantly and
visibly. This is the emotional core of the game — *you put the phone down and the
tree changed* — so it must be a visible animation, not a number in a log.

## 6. Health states and death

```
target = 100 · C
dH/dt  = H < target ?  +heal · (target - H)/100
                    :  -harm · (H - target)/100

heal = 3.2 %/h · sp.vigor
harm = 1.1 %/h · (1 - sp.resilience)
```

Exponential approach in both directions: no cliffs, no NaN, self-limiting.
**Healing is ~3× faster than harm** — the formula, not a special case, is what
makes trees hard to kill and satisfying to rescue.

State thresholds use hysteresis so the UI never flickers:

| State | Enter | Leave | Glyph | Word |
|---|---|---|---|---|
| Thriving | H ≥ 88 ∧ C ≥ 0.90 | H < 82 | ✦ | Thriving |
| Healthy | H ≥ 70 | H < 64 | ● | Healthy |
| Stressed | H ≥ 45 | H < 39 | ◐ | Stressed |
| Ailing | H ≥ 20 | H < 15 | ◒ | Ailing |
| Critical | H < 20 | H ≥ 26 | ○ | Needs help |
| Dormant | offline > 72 h | first care on return | ◌ | Resting |

### Death is deliberately hard to reach

```
if state == critical:  criticalHours += dt
else:                  criticalHours = max(0, criticalHours - 2·dt)

death requires:  criticalHours ≥ 120        // five days of sustained critical
            AND  criticalSightings ≥ 2      // player has SEEN it critical twice
            AND  a care notification was delivered at least once
```

The second and third clauses matter more than the first. **No player loses a tree
they never had a chance to save.** Recovery also forgives at double rate, so one
good watering session erases two days of the counter.

And death is not deletion. The tree becomes a **snag** — standing deadwood that:

- still occupies its slot until the player chooses to clear it,
- attracts woodpeckers and beetles (new discoveries, genuinely),
- counts at 0.4× weight toward ecosystem diversity,
- yields **2 Heartwood Seeds**: one of the parent species, one wildcard roll,
- confers a permanent **Legacy** bonus to the next tree in that slot (+8% vigor).

An ecologist would tell you a standing dead tree is one of the most biodiverse
objects in a forest. Using that fact as the failure state is both truthful and
the gentlest possible landing.

## 7. Dormancy — the long-absence model

This exists because of Charter C1.

> **Corrected in implementation.** Dormancy keys off `lastInteractionAt` — how
> long the player has been away at each absolute instant — *not* off the size of
> the catch-up window. Keying it off window size makes the result depend on how
> the elapsed time was chunked, which breaks §1's composition property. See
> [17 §1](17-phase-1-week-1-report.md).

Once the player has been away more than 72 hours:

```
W → asymptote toward W_rest = 25    with τ = 36 h
N → asymptote toward N_rest = 30    with τ = 48 h
H: dH/dt = -0.25 · harm · (H - 15)/100,  floored at H = 15
Growth: paused
Events: paused (no pests, no disease, no animal churn)
```

A player returning after three weeks finds a **resting** forest at ~15–20 health:
visibly in need of care, fully recoverable within a day, nothing lost. They also
find three weeks of accrued Dew, rain journal entries, and any discoveries that
were pending.

This is closed-form and keyed on absolute time, so it composes exactly like §1.

## 8. Clock integrity

```dart
TrustedElapsed compute(SaveMeta last, ClockReading now) {
  final wall = now.wallClockMs - last.wallClockMs;
  if (wall < 0) return TrustedElapsed.zero(anomaly: ClockAnomaly.rewind);

  if (now.bootId == last.bootId) {
    final mono = now.monotonicMs - last.monotonicMs;
    return TrustedElapsed(min(wall, mono));        // both must agree
  }
  // Device rebooted: monotonic clock is useless as a cross-check.
  return TrustedElapsed(min(wall, MAX_RESUME_MS)); // MAX_RESUME = 36 h
}
```

- `monotonicMs`: Android `SystemClock.elapsedRealtimeNanos()`; iOS
  `clock_gettime(CLOCK_MONOTONIC)` — on Darwin this advances during sleep, which
  is what we want.
- `bootId`: derived from `wallClock − monotonic`, bucketed to the second.
- `simTime` is monotonic in the save and never decreases, so a wall-clock rewind
  simply produces zero progress rather than negative progress.
- Offline reward accrual (Dew, rain, journal events) is additionally capped
  **per calendar day**, so setting the clock forward repeatedly yields nothing.
- A `simTimeHigh` watermark is mirrored outside the main database (iOS Keychain,
  which survives reinstall; Android `EncryptedSharedPreferences` excluded from
  auto-backup). Restoring an old save is detected and the game silently declines
  to re-grant already-consumed time. **It never accuses the player of anything.**

Per Charter and the brief: this is intentionally not an invasive anti-cheat.
There is no server, no attestation, no device fingerprinting. A determined
offline player can cheat, and the cost of that is zero because there is no
competitive surface.

## 9. Events (deterministic)

```
rng = xorshift128(hash(worldSeed, treeId, floor(t / 3600_000)))
```

Hourly slots keyed on **absolute** time, so an event either happens or does not,
regardless of how the elapsed window was chunked. Probabilities per hour:

| Event | Probability |
|---|---|
| Pest | `0.004 · (1 + 3·max(0, (W-80)/20)) · (1 - sp.pestResistance) · (1 - 0.6·C)` |
| Fungus | `0.020` — only after `W > 82` sustained ≥ 6 h |
| Nutrient burn | not random: `N > nutrition.max + 18` sets the affliction directly |
| Animal visit | `0.05 · attract(tree)` |
| Flowering | species-gated, seasonal, `sp.floweringChance` at stage ≥ young |
| Rare discovery | `0.0008 · ecosystemScore · (1 + streakBonus)` |
| Mutation (on stage-up) | `sp.mutationChance`, one roll per stage transition |

## 10. Ecosystem scoring

```
attract(tree)  = C · stageWeight[stage] · (sp.animalAttraction + (flowering ? 0.6 : 0))
ecosystemScore = Σ attract(tree) · diversityFactor
diversityFactor = 1 + 0.15·(distinctSpecies − 1) + 0.10·(distinctFamilies − 1)
```

Diversity is *mechanically* rewarded, not just narratively. Five Oaks score worse
than three Oaks and two Birches. This is how the brief's stated long-term goal —
"a thriving, diverse and balanced ecosystem" — becomes something the player can
actually optimise.

## 11. Weather

Deterministic from `hash(worldSeed, dayIndex)`, generated as a **forecastable**
sequence: the game can show a real two-day forecast (unlocked at level 9) because
future weather is a pure function of the seed.

Per biome, a Markov chain over `{sunny, cloudy, rain, storm, fog}` with
season-dependent transition matrices. Rain adds `+2.5 %/h` moisture (storm
`+6 %/h`), which is exactly the mechanism by which a careless player gets
overwatered — and why the forecast is a meaningful unlock rather than decoration.
