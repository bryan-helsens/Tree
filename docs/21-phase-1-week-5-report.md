# 21 — Phase 1, Week 5: interaction, the tree panel, and the first HUD

Screens in [`docs/screens/`](screens/), captured from the real widget tree.

## 1. Interaction is simulation-first, and there is a test for every link

The required flow, implemented exactly:

```
tap → validate → domain action → GameState → WorldProjector
    → FoliageState → renderer reacts → visual feedback
```

`GameController` is the only thing that may change the game. It holds the
state, applies actions through `Actions`, and re-projects. It has no access to
appearance and exposes none.

The part worth calling out is **how the watering animation is triggered**. It is
not played by the button. `Tree.timesWatered` and `timesFed` are persisted
domain counters; `CareEffect` watches them and plays a burst when one
increments. So:

- A successful action increments a counter → the burst plays.
- A **refused** action increments nothing → no burst, with no special case
  anywhere in the UI.

The animation is a consequence of state in the strictest available sense: it is
driven by a number that is saved to disk.

`interaction_flow_test.dart` pins the chain — appearance changing because a
vital changed, the resource actually being spent, the counter incrementing, a
refused action changing *nothing*, and simulated time alone changing appearance
with no player action at all.

Two design invariants also have tests:

- **Watering does not visually fix a sick tree.** Two waterings bring moisture
  to comfortable and the tree still sags, because turgor reads health too.
- **Scorch outlives the excess.** Nutrition returns to band; the damage still
  shows until the affliction decays.

## 2. Three real bugs found by looking at the screens

### The preview warned about the wrong thing

`ActionPreview.leavesBand` was `!band.contains(to)` — so watering a parched
tree from 26 to 37 was flagged **"would overshoot"**, when 37 is still *below*
the ideal 45. A warning that fires on progress teaches the player to distrust
warnings.

It now means what it says: `to > band.max`. In the screens, `26 → 37` is
silent and `44 → 66` warns.

### The accessibility geometry had drifted from the visual geometry

`ForestScene._tree` and `ForestView.treeRect` each carried their own copy of
the placement arithmetic. A composition tweak updated one and not the other,
leaving the painter at `height / 620` and the semantic layer at `height / 380`
— **every semantic node in the wrong place**, silently.

`ForestScene.placeTree` is now the single source, called by both, and a test
asserts the painter's placement and the semantic rect agree at three depths and
three positions. This is the failure mode the "build accessibility alongside"
rule exists to prevent, and it still happened; a shared function is the only
thing that actually prevents it.

### The HUD and the care buttons clipped on a narrow phone

`RenderFlex overflowed by 11 pixels` at 360 dp. The HUD row is now a `Wrap`,
the care button's label is `Flexible` with ellipsis, and its preview line wraps.
A HUD that clips is worse than one that takes two lines.

## 3. The tree panel

A sheet over the living world, capped at 56% height so the tree stays visible —
watering it and watching it respond happen in the same glance.

Deliberately not a spreadsheet:

- **The ideal range is drawn on the bar**, with a ghost showing where an action
  would land. The player sees the target as a *region* and learns that the top
  of the bar is not the goal. A bare percentage teaches the opposite.
- **What the tree needs is one sentence**, not a table.
- Numbers appear only where they inform a decision: the vital, and what the
  action would change it to.
- Health state carries a glyph, a word *and* a colour, never colour alone.
- Afflictions appear under "what you can see", each with its cause in plain
  language.
- The action row is **pinned below the scroll**, because the two things a
  player opened the panel to do must never be below the fold.

Note that "Healthy" can sit next to "Thirsty" — and should. Health is 68 and
fine; the tree is simply dry. The pill reports condition, the sentence reports
need, and separating them is what lets a player understand that a thirsty tree
is not a dying one.

## 4. The HUD

Level and XP, water, feed, streak — what you hold, because it is what the care
buttons spend. Then one call to action, the largest thing on screen after the
forest: **"Put your phone down · Your forest grows while you are away."**

The loop is legible in the first five seconds without a tutorial. The call is
absent while a tree panel is open: two competing primary actions on one screen
is one too many.

The hint varies with simulated weather — during rain it reads "Rain is watering
your forest while you are away" — so even the copy is downstream of the
simulation.

## 5. Kept, as instructed

`FoliageState` in `grow_domain`; species tolerance data-driven with no
per-species rendering branch; health influencing turgor; afflictions outliving
their cause; accessibility sharing the visual layout calculation (now
enforced); reduced motion reducing rather than freezing; Tree Lab on the real
chain; the placeholder atlas as a placeholder. One Oak, no new content.

## 6. Open

- **A faint ghost of the focus call renders behind the open sheet** in the
  captured screens. `showCall` is false in that state and the widget is not
  built, so the cause is not yet identified — recorded as unverified rather
  than claimed fixed.
- Emoji render as tofu in the test harness (DejaVu has no emoji coverage). A
  device-font issue in the harness, not the app.
- The focus session flow itself is stubbed: the button is wired to a no-op
  pending the session state machine.
- Snow, sun occlusion and the wet-ground boundary remain from Week 4.
- The quality bar stays open until commissioned canopy art is integrated.

## 7. Next

- The focus session: picker, running state, completion, and the growth
  injection that is the emotional core of the product.
- Persistence, so a closed app comes back correctly.
- The welcome-back sequence.
