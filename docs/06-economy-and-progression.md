# 06 — Economy & Progression

## 1. Resources — deliberately few

| Resource | Symbol | Role | Cap |
|---|---|---|---|
| Water | 💧 | Primary spend, earned constantly | `15 + 2·⌊level/2⌋`, max 45 |
| Nutrients | 🌱 | Scarce spend, gates optimal growth | `5 + ⌊level/3⌋`, max 20 |
| Seeds | 🌰 | Unlock new trees; species-specific | uncapped |
| Forest XP | ⭐ | Progression only, never spent | — |

Four is the ceiling. No premium currency, no energy, no timers-with-a-skip-price.
Decorations and rare items are inventory objects, not a fifth currency.

**Spend values**

```
Water action:     +11 × sp.absorption  moisture   (1 Water)
Nutrient action:  +22                  nutrition  (1 Nutrient)
```

A young Oak loses ~23% moisture/day (see [05 §3](05-simulation.md#3-water)), so it
needs roughly **two Water per day** — about one focus session. Five mature trees
need ~12/day, against an income of ~15–17. The economy is designed to be *just*
tight enough that you choose which tree gets the last unit.

## 2. Focus sessions — the primary faucet

```
GP(m)        = 10 · m^0.8                       Growth Points for m minutes
fatigue(n)   = [1.00, 1.00, 0.85, 0.70, 0.55, 0.40][min(n,5)], floor 0.30
streakMult   = 1 + min(0.50, 0.05 · streakDays)
integrity    = 0.35 … 1.00                      never 0 — Charter C2
GP_final     = round( GP(m) · fatigue(n) · streakMult · integrity )
```

Daily soft cap: once cumulative GP for the day exceeds **900**, further GP is
multiplied by 0.2. Session length is capped at 120 minutes.

**Conversion is deterministic, not random** — a player should be able to predict
a reward before committing 45 minutes to it:

```
Water     = ⌊GP_final / 45⌋
Nutrients = ⌊GP_final / 190⌋
XP        = GP_final
Seed roll = clamp(GP_final / 2500, 0, 0.35)
```

| Duration | GP | 💧 | 🌱 | ⭐ | Seed % | GP/min |
|---|---|---|---|---|---|---|
| 10 min | 63 | 1 | 0 | 63 | 2.5% | 6.3 |
| 20 min | 110 | 2 | 0 | 110 | 4.4% | 5.5 |
| 30 min | 152 | 3 | 0 | 152 | 6.1% | 5.1 |
| 45 min | 210 | 4 | 1 | 210 | 8.4% | 4.7 |
| 60 min | 265 | 5 | 1 | 265 | 10.6% | 4.4 |
| 90 min | 366 | 8 | 1 | 366 | 14.6% | 4.1 |
| 120 min | 461 | 10 | 2 | 461 | 18.4% | 3.8 |

The `m^0.8` exponent gives the diminishing returns the brief asks for: minute 120
is worth 60% of minute 10. But note what the numbers actually produce —
**2 × 30 min (6💧) slightly beats 1 × 60 min (5💧)**, while the first two sessions
of a day are both at full fatigue weight. The equilibrium the maths pushes toward
is *two to three medium sessions a day*, which is exactly the behaviour the
product wants. Longer sessions are not punished; their marginal minute is simply
worth less, which removes any incentive to fake a six-hour session.

**Deep Focus bonus.** Any session ≥ 45 minutes grants, once per day: **+1
Nutrient** and **+8% rare-discovery chance for 24 h**. Long sessions therefore win
on *quality* (rare things) while short ones win on *quantity* — a better answer
than tuning a single scalar in either direction.

**Direct growth injection.** `ΔGrowth = GP_final × 0.02` percent of the current
stage, applied with a visible animation on the completion screen. This is the
moment the whole product exists for.

## 3. Other faucets

| Source | Yield | Notes |
|---|---|---|
| **Dew** (passive) | +1 💧 / 3 h, cap 5 | Offline only. Guarantees Charter C5. |
| Daily challenges (3) | 2💧 / 1🌱 / 60⭐ each | One free reroll per day |
| Weekly challenges (3) | 1🌰 / 4💧 / 300⭐ | Reset Monday local |
| Rain | +2.5 %/h moisture | Free water — and the overwatering trap |
| Level-up | 3💧 + 1🌱 + unlock | |
| Streak day 3 / 7 / 14 / 30 | seed / rare roll + cosmetic / decoration / rare seed | |
| Screen-time goal met | up to +120 GP | Android only; iOS = the one-bit variant ([07](07-screen-time-integration.md)) |
| Snag (tree death) | 2 Heartwood Seeds + Legacy | The soft landing, not a punishment |

## 4. Sinks

Water and Nutrients are consumed by care. Later sinks (post-MVP) are the
**Compost Bin** (level 7 — converts prunings into Nutrients over real time) and
**decorations**, which cost Seeds and rare items rather than core resources so
they never compete with keeping trees alive.

There is deliberately **no sink that converts money into resources**, per
[Charter C8](00-design-charter.md#c8--no-monetisation-surface-in-the-mvp).

## 5. Daily budget, modelled

A moderately engaged player, level 6, five trees:

```
income   2.5 focus sessions ≈ 8 💧, 1 🌱, 380 ⭐
       + daily challenges     ≈ 4 💧, 1 🌱, 180 ⭐
       + dew                  ≈ 5 💧
       + rain                 ≈ 1–2 💧 equivalent
       ─────────────────────────────────────────
                              ≈ 17 💧, 2 🌱, 560 ⭐

outgo    5 trees × ~2.1 💧    ≈ 11 💧
         optimal feeding      ≈ 2 🌱
```

Comfortable surplus on Water (so nobody is blocked), genuine scarcity on
Nutrients (so feeding is a decision). If the player skips focus sessions entirely
they run a small Water deficit and their trees drift toward Stressed — noticeable,
recoverable, never fatal.

## 6. XP and levels

```
xpToNext(n) = round(90 · n^1.45)
```

| Level | XP for level | Cumulative | ~Days @560/day |
|---|---|---|---|
| 2 | 90 | 90 | 0.2 |
| 3 | 246 | 336 | 0.6 |
| 4 | 443 | 779 | 1.4 |
| 5 | 672 | 1,451 | 2.6 |
| 6 | 928 | 2,379 | 4.2 |
| 8 | 1,512 | 5,100 | 9 |
| 10 | 2,537 | 9,113 | 16 |
| 15 | ~4,900 | ~25,000 | 45 |
| 20 | ~8,100 | ~53,000 | 78 |

Effective pace is faster than the last column because XP income scales with
forest size. Levels 1–8 land inside the first week and carry the MVP.

## 7. Unlock table — every level gives a *mechanic*, not a skin

| Lv | Unlock | Why it matters mechanically |
|---|---|---|
| 2 | Second planting slot | First real resource-allocation decision |
| 3 | Ground cover (moss, ferns) | `soilRetention ×0.85` — reduces water demand |
| 4 | Silver Birch seed | A species with a *different* water band; teaches per-species care |
| 5 | Pollinator flowers + Animals tab | First spawn condition the player can engineer |
| 6 | Plot expansion 4 → 7 slots | Forest becomes a system, not a set of trees |
| 7 | Compost Bin | A time-based Nutrient sink/faucet — the first "engine" |
| 8 | Soil types per slot | Placement becomes strategic |
| 9 | Two-day weather forecast | Turns rain from a surprise into a plan |
| 10 | **Blossom Valley biome** | New species pool, new light/temperature bands |
| 12 | Nesting boxes | Converts visiting birds into resident birds |
| 15 | Japanese Maple line | First genuinely demanding species |
| 18 | Seasons enabled | Global modifiers on growth and flowering |
| 20 | Ecosystem tier | Animals reproduce; forest generates passive Nutrients |

Levels 1–8 are MVP scope. Everything from 9 up is content the architecture
supports without engine changes.

## 8. Streaks

A streak day is earned by **completing any focus session ≥ 10 minutes**, evaluated
in the device's local timezone.

- `streakMult` on GP: `1 + min(0.50, 0.05 · days)` — caps at 10 days so it never
  becomes coercive.
- **Streak Shield:** the player holds up to 1, regenerating every 10 days. Missing
  a day consumes the shield silently and the streak continues. The player is told
  afterwards ("Your shield covered yesterday 🛡️"), never warned beforehand — a
  countdown to losing something is precisely the anxiety this product exists to
  reduce.
- Losing a streak with no shield drops it to 0 but grants a **Second Wind**: the
  next streak rebuilds at double rate for three days.

## 9. Balancing method, not guesswork

`tools/balance_sim` runs headless 30-day simulations across archetypes — *daily
2-session player, weekend-only player, one-session-a-week player, 14-day
absentee, deliberate overwaterer* — and emits CSV of resource balance, health
distribution, level curve and time-to-first-death.

Ship criteria before Phase 2:
- 14-day absentee: **zero deaths**, all trees recoverable within one session.
- Deliberate overwaterer: reaches Stressed within a day, understands why (the
  soil is visibly saturated), recovers within a day, **never** reaches Critical
  from a single mistake.
- Weekend-only player: still gains a level per week.
- No archetype ever reaches a state with zero available actions.
