# 08 — Animation Strategy

Animation is not decoration on this project; it is the product. The brief's line
*"the world should NEVER feel like a collection of static PNG images"* is the
hardest requirement to satisfy cheaply, and it drives the biggest technical bet
in this architecture.

## 1. The bet: procedural trees, not sprite stages

Sprite-based growth stages do not survive contact with the design requirements.
Count the assets:

```
7 growth stages × 5 health states × 4 seasons × 2 flowering states × 30 species
= 8,400 hand-drawn trees
```

And after all that, growth would still *pop* between stages instead of being
continuous, and every tree of a species would be identical.

Instead: **a tree is a deterministic function of `(species.branchRules, treeSeed,
growth01)`.** See [ADR-0002](adr/0002-procedural-trees.md).

This gives, for free:
- continuous growth — the trunk thickens and branches extend between stages, so
  "watch it grow" is literally true;
- variety — every tree of the same species is visibly a different individual;
- health as **uniforms** rather than art (droop, pallor, scorch, wetness,
  sparkle are `double` values in `[0,1]` lerped from simulation state);
- seasons and flowering as palette and instance-density changes;
- an asset budget measured in kilobytes.

The cost is that "procedural" and "beautiful" are far apart, and closing that gap
is a tuning problem — which is why `tools/tree_lab` is a Phase 1 deliverable
([03](03-project-structure.md#toolstree_lab-deserves-special-mention)).

## 2. Tree geometry

```dart
TreeSkeleton generate(BranchRules rules, Seed seed, double growth01);

class TreeSkeleton {
  final List<Branch> branches;        // ≤ ~400 segments at ancient stage
  final List<LeafCluster> clusters;   // anchor points for instanced leaves
  final Rect bounds;
}

class Branch {
  final Offset a, b;
  final double widthA, widthB;
  final int depth;
  final double emergeAt;   // growth01 at which this branch starts appearing
  final double phase;      // per-branch wind phase offset
  final double flex;       // ∝ 1 / width — thin twigs move most
}
```

Generation is a seeded recursive walk: each node spawns `childrenPerNode`
branches at `branchAngle ± angleJitter`, scaled by `lengthDecay` and `taper`,
biased upward by `phototropism` and downward by `gravityDroop` in proportion to
length/width ratio.

**No popping:** a branch with `emergeAt = 0.62` scales from 0 → 1 over the growth
window `[0.62, 0.72]`, so new growth *unfurls*.

**Regeneration policy:** the skeleton is rebuilt only when `growth01` changes by
more than 0.005 — a handful of times per session — and cached as a flattened
vertex/index buffer. Per-frame work is a transform pass over ≤400 segments, not a
regeneration.

## 3. The wind field — one system animates everything

A single global function drives the whole world:

```
wind(t, y) = base(t) + gust(t) · noise2(t · 0.13, y · 0.004)
base(t)    = A · sin(t·0.35) + 0.4A · sin(t·0.77 + 1.1)
gust(t)    = smoothstep over a Poisson-ish gust schedule seeded from the day
```

Per branch, per frame:

```
θ = θ_rest + wind(t, branch.midY) · branch.flex · sin(t·ω + branch.phase)
```

Grass blades, leaf clusters, drifting particles, cloud drift, water ripples and
the Rive animals' `windLean` input all read **the same field**. That shared source
is why the scene reads as one place with weather in it, rather than as several
independently looping animations — which is the specific failure mode that makes
cozy games feel cheap.

Weather modulates a single amplitude parameter. A storm is the same code with
`A` tripled and rain particles enabled.

## 4. Leaves and health

Leaves are **instanced textured quads** from a single atlas, positioned at cluster
anchors with seeded jitter, drawn in one `drawAtlas` call per tree (or per canopy
layer). Density is a curve over `growth01`.

Health becomes shader/tint parameters, not new art:

| Sim input | Visual parameter | Effect |
|---|---|---|
| `bandLow(water)` | `droop` 0→1 | cluster rest angle biases downward, wind amplitude ×(1−0.5·droop) |
| `bandLow(nutrition)` | `pallor` 0→1 | leaf tint lerps toward desaturated yellow-green |
| `bandHigh(nutrition)` | `scorch` 0→1 | edge-darkening mask blends in; brown speckle at high values |
| `water > 85` | `wetness` 0→1 | soil shader darkens, specular sheen, puddle SDFs, slower sway |
| `fungus` affliction | `fungus` 0→1 | sprite decals at cluster bases |
| `C > 0.9 ∧ H > 88` | `sparkle` 0→1 | occasional single-pixel-bloom particles, ~1 every 4 s |

All of these are `lerp`ed toward their targets over ~2 seconds, so recovery is
visibly *gradual* — the brief's section 10 requirement — and a watering action
produces a continuous change rather than a snap.

## 5. Fragment shaders

Written as GLSL, compiled to SkSL by the Flutter toolchain, loaded via
`FragmentProgram`:

| Shader | Use |
|---|---|
| `soil.frag` | wetness, darkening, puddle SDFs, mulch texture |
| `godrays.frag` | radial light shafts through the canopy, time-of-day driven |
| `atmosphere.frag` | fog, haze, night vignette, colour grading per time of day |
| `water.frag` | pond ripples (post-MVP wetlands biome) |
| `season.frag` | full-scene palette LUT blend across seasons |

Each has a `QualityTier.low` variant that is a flat gradient. No shader is ever
required for legibility.

## 6. Rive for animals

Procedural generation is right for plants and wrong for characters. A bird
landing, cocking its head, and taking off is charm that comes from an animator's
hand.

Each animal is one Rive artboard with a state machine whose states map exactly to
the lifecycle in the brief: `spawn → travel → idle → interact → exit`, with
inputs `windLean`, `alertness`, `timeOfDay`. The Dart side drives the *path*
(bezier flight lines, perch selection via the spatial hash) and sets inputs; Rive
owns the *performance*.

MVP ships two: a robin and a cabbage white butterfly. Both are on-screen only when
their spawn conditions hold, so seeing one is information about the forest's
state, not ambience.

## 7. Performance budget

Target: **60 fps on Pixel 6a and iPhone SE (3rd gen)** with 5 trees, weather,
2 animals, and a bottom sheet open over the live world.

| Item | Budget |
|---|---|
| Tree transform + emit, 5 trees | 2.5 ms |
| Leaf `drawAtlas`, ≤ 2,400 instances | 2.0 ms |
| Grass + particles | 1.5 ms |
| Shaders (soil, atmosphere, godrays) | 3.0 ms |
| Rive, 2 artboards | 1.5 ms |
| Flutter UI layer | 2.5 ms |
| Headroom | 3.6 ms |

**Quality tiers**, chosen by a startup benchmark and overridable in Settings:

| | Low | Medium | High |
|---|---|---|---|
| Target fps | 30 | 60 | 60 |
| Leaf instances / tree | 180 | 420 | 800 |
| Particles | off | 60 | 200 |
| Shaders | flat gradients | soil + atmosphere | all |
| Godrays | off | off | on |

## 8. Reduced motion

`MediaQuery.disableAnimations` plus an in-app toggle. When on:
wind amplitude ×0.15, no ambient particles, animals fade in/out at their
destination instead of travelling, UI transitions become cross-fades, parallax
off, no screen shake, no sparkle. **The world still moves slightly** — going
completely static would remove the thing the player is here for — but nothing
drifts, pulses or flies.

## 9. UI feel

Motion tokens live in `design_system/motion/`, and no widget may hard-code a
`Duration` or `Curve`.

| Action | Feedback |
|---|---|
| Water | button depresses → watering-can tilt → droplet particles arc → soil darkens over 1.2 s → moisture bar fills with a slight overshoot → soft splash + light haptic |
| Fertilise | granule particles scatter → soil texture shifts → 2 s later a subtle green pulse travels up the trunk into the canopy |
| Growth stage up | camera eases in 6% → branches unfurl over 2.5 s → one-line caption, no modal |
| Level up | XP bar fills → badge scales with an overshoot spring → world briefly warms in colour → reward card slides up |
| Discovery | mystery seed shakes → light bloom → card flips → species revealed with rarity flourish |

Every one of these is skippable by tapping, and none of them blocks input for more
than 400 ms. **Discovery is the only full-screen moment in the game.**
