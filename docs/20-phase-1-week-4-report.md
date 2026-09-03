# 20 — Phase 1, Week 4: the world, wired to the simulation

The loop from the brief is now connected end to end:

> real simulation state → tree growth → foliage appearance → environmental
> world → player interaction

Evidence in [`docs/art-review/`](art-review/), rendered through the shipping
pipeline.

## 1. Appearance is now a consequence, not an input

`FoliageState` moved into `grow_domain`, because it is the contract between the
simulation and the renderer and neither side should depend on the other to see
it. `grow_sim` gained `WorldProjector`, which turns a `GameState` into a
`WorldSnapshot`: the flattened, render-oriented projection
[02 §3](02-system-architecture.md#3-data-flow-and-threading) called for.

Every visual property is derived from vitals and the species' own bands:

| Look | Comes from |
|---|---|
| droop | moisture below band ÷ that band's `tolLow`, or poor health |
| pallor | nutrition below band |
| scorch | nutrition above band, or a standing nutrient burn |
| wetness | moisture above band, or rain falling now |
| sparkle | thriving state *and* comfort > 0.9 |
| bareness | health below 40 |

Because each term is normalised by **that species' own tolerance**, a species
with a tight nutrient ceiling shows scorch sooner than a forgiving one with no
per-species art and no branch in the code. `w_vitals_to_world.png` is the proof:
six cells where only water, nutrition and health differ.

Two consequences worth naming:

- **A sick tree sags even just after watering.** Turgor reads from health as
  well as moisture, or watering would appear to fix everything instantly.
- **Scorched leaves do not un-scorch** the moment nutrition returns to the
  band; the affliction keeps showing until it decays.

Condition changes ease in over about a second via `approachFoliage`, which is
framerate-independent — one 100 ms step lands exactly where ten 10 ms steps do,
and there is a test for it.

## 2. The world scene

`SkyPalette` owns every environmental colour, so sky, light, haze and ground
tint cannot drift out of agreement. Time of day is continuous — there is no
"night mode" palette to keep in sync with a "day mode" one. Sun height comes
from a real solar term, so dawn and dusk are the low, warm, long-shadowed
moments they should be, and the sun sets rather than blinking out.

`ForestScene` composes sky, sun or moon and stars, drifting cloud, a hazed
distant treeline, the plot ground, trees at depth, weather, and a restrained
vignette. `w_day_cycle.png` and `w_weather.png` show both axes.

Depth comes from **atmospheric perspective**, not drop shadows: distant trees
wash toward the sky's haze colour and read smaller.

> A bug worth recording: the first implementation applied that haze as a
> rectangle over each tree's bounding box with `srcATop`, which hazes whatever
> else is inside that box — the sky and ground included — and showed up as a
> grey panel around every distant tree. Aerial perspective belongs in the
> tree's own bark and foliage colours, where it costs nothing extra.

Rain intensity follows the simulated `rainRate`, so a shower looks like a
shower and the drizzle between showers looks like drizzle.

## 3. Accessibility, built alongside

`ForestView` renders the scene and, in the same layout pass, positions a real
`Semantics` node over every tree carrying the description `WorldProjector`
produced — species, stage, state, both vitals against their ideal ranges, the
limiting factor when the tree needs help, and any afflictions.

Two things this placement buys:

- The geometry that positions a tree is the *same function* that positions its
  semantic node (`ForestView.treeRect`), so they cannot disagree. Retrofitting
  would have meant computing it twice.
- **A seedling stays reachable.** A young tree is a few pixels tall; its touch
  target is expanded to at least 48 dp in both axes.

Reduced motion drops wind to 15% rather than freezing the world: going fully
static would remove the thing the player is here for.

Tests cover labelling, tap routing to the right tree, node placement over the
drawn tree, the minimum target, and rendering across every weather at four
times of day without throwing.

## 4. Tree Lab tunes the real chain

The lab's sliders are now **simulation inputs** — water, nutrition, health,
weather, time of day — and appearance comes back through the same
`WorldProjector` the game uses. The water and nutrition sliders draw the
species' ideal band behind the track, the way the tree panel will, and a
readout shows the resulting comfort, limiting factor and uniforms.

The stage draws the full `ForestScene` by default, so tuning happens against
real sky, light, weather and ground rather than against a tree on a flat
rectangle. Skeleton-only and bare-tree views remain for structure work.

`arch_check` now permits `tree_lab` to reach across the whole stack, with the
reason recorded next to the rule: it is a development tool, and reaching the
real chain is the entire point of it.

## 5. Known gaps

- **Snow renders as rain streaks.** Out of MVP scope; the weather sheet shows
  it honestly rather than hiding the cell.
- **The sun stays visible through heavy cloud.** It should occlude.
- **The plot/middle-distance boundary is a hard line** when the soil is wet.
- The canopy is still the placeholder atlas. The quality bar is not passed
  until commissioned art is in.

## 6. Next

- Tree detail panel and the water/feed actions against the live world.
- The HUD, and the first full screen rather than a scene.
- Commissioned canopy art when available.
