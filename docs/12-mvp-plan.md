# 12 — MVP Plan

## 1. Scope — IN

**World**
- One biome: Woodland.
- One plot, 4 slots (2 unlocked at level 1, 3rd at level 2, 4th at level 6).
- Day/night cycle with real lighting changes.
- Weather: sunny, cloudy, rain (no storm/snow/fog).

**Trees**
- Two species: **Pedunculate Oak** (starter, forgiving) and **Silver Birch**
  (level 4 unlock, thirstier, faster, tighter nutrient band).
- Six growth stages, procedurally rendered, continuous growth between stages.
- Full vitals simulation, over- and under-watering, over- and under-feeding,
  health states with recovery, afflictions (pest, fungus, nutrient burn),
  dormancy, snag on death.

**Gameplay**
- Focus sessions: 10/20/30/45/60 + custom, Gentle mode on both platforms,
  **Grounded mode on Android**, iOS Grounded flagged off pending entitlement.
- Water / Nutrients / Seeds / XP economy with Dew trickle.
- 3 daily challenges (1 reroll) + 3 weekly challenges.
- Streak with Shield and Second Wind.
- Levels 1–8 with the real unlocks from
  [06 §7](06-economy-and-progression.md#7-unlock-table--every-level-gives-a-mechanic-not-a-skin).

**Ecosystem**
- Two animals with full lifecycle animation: **robin** (perches on branches of
  mature trees) and **cabbage white butterfly** (visits flowering plants).
- Ground cover plants (level 3) with a real `soilRetention` effect.

**UI**
- Onboarding, Forest, tree detail sheet, Focus flow, Satchel, Field Guide,
  Progression, Welcome Back, Settings.

**Systems**
- Local persistence with backup rotation and migration tests.
- Local notifications, all four channels, predictive care nudges.
- Audio: ambient bed, wind layer, birds, 8 interaction SFX, all independently
  mutable.
- Accessibility: semantics tree, reduced motion, dynamic type, non-colour state.

## 2. Scope — OUT (built to be added, deliberately absent)

Multiplayer · social · accounts · cloud sync · any monetisation · shop · more
than 2 species · more than 2 animals · biomes beyond Woodland · seasons · storm /
snow / fog · decorations · compost bin · soil types · nesting boxes · leaderboards ·
third-party analytics · iOS Sanctuary mode · widgets.

Every one of these has a defined seam in the architecture. None requires an engine
change to add.

## 3. Acceptance criteria

The MVP is done when a first-time player, unassisted, on a real device, can do all
thirteen of the brief's success criteria — verified as a scripted playtest, not an
opinion:

| # | Criterion | How it is verified |
|---|---|---|
| 1 | Start with a seed | Onboarding completes in < 90 s |
| 2 | Watch it grow | Stage 1→2 within the first session (~20 min) |
| 3 | Understand its needs | Tester states the water band unprompted after opening the sheet once |
| 4 | Earn water/fertiliser | Completes a session and names the reward |
| 5 | Make resource decisions | Reaches a state with 2 trees and insufficient Water for both |
| 6 | Accidentally overwater | Instrumented: ≥60% of testers push a tree above its band in week 1 |
| 7 | Understand consequences | Tester attributes the drooping to overwatering without being told |
| 8 | Help it recover | Tree returns to Healthy within one day of correct care |
| 9 | Complete a focus session | Completion rate > 70% for started sessions |
| 10 | Feel rewarded for it | Post-session survey ≥ 4/5 on "felt worth it" |
| 11 | Level up | Reaches level 3 on day one |
| 12 | Emotional attachment | Tester names their tree, or objects to the idea of deleting it |
| 13 | Want to return | Day-2 return > 40% in the playtest cohort |

Plus engineering gates:

- 60 fps sustained on Pixel 6a and iPhone SE 3 in the busiest scene.
- Cold start to interactive world < 1.8 s on those devices.
- 30-day headless simulation across all five player archetypes with **zero
  unintended deaths** and no state with zero available actions.
- `simulate(a→c) == simulate(a→b) + simulate(b→c)` property test passing over
  10,000 randomised windows.
- Kill the app at 40 randomised points; state always restores correctly.
- Install size < 40 MB, APK/IPA.

## 4. The first five minutes, scripted

The brief says the first five minutes must already feel polished. This is the
literal beat sheet, and it is a design deliverable, not an emergent property:

```
0:00  A dim screen. Wind. A hand places a seed in soil. No logo, no menu.
0:15  "This is your forest." Two lines of text. One tap.
0:30  The seed is in the ground. The camera pulls back to reveal a small clearing,
      grass moving, morning light. The world is already alive.
0:45  A prompt: the soil is dry. One Water in the satchel. The player waters.
      Droplets, soil darkening, the seed shifts.
1:10  A sprout breaks the surface. Stage 1 → 2. No modal — the camera just eases in.
1:30  "It'll grow on its own. It grows faster when you're not here."
      → the pitch, delivered once, at the moment it makes sense.
1:45  Focus tab. "Put your phone down for 10 minutes. See what happens."
2:00  Timer starts. The screen dims to almost nothing. The player puts the phone
      down. (If they don't, nothing bad happens.)
12:00 Notification: "Your focus session is complete. The forest grew."
12:10 Return: growth injection animation, +1 Water, +63 XP, level 2.
      The sprout is visibly taller than it was.
12:30 Level 2 unlocks a second slot. A seed is waiting.
```

The pitch is delivered at 1:30, *after* the player has already felt the world be
alive, and it is never repeated.

## 5. Content pipeline, proven in the MVP

Two species is enough to prove the pipeline is real. The test: **adding the third
species must require only a JSON entry, a leaf-atlas index, and a palette** — zero
Dart changes. If adding species #3 needs code, the data-driven architecture failed
and it is a Phase 2 blocker, not a Phase 3 problem.
