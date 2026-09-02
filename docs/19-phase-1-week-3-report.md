# 19 — Phase 1, Week 3: the hybrid Oak

The hybrid is implemented and validated on one species. Evidence in
[`docs/art-review/`](art-review/), all rendered through the shipping pipeline.

## 1. The branch-attachment defect is fixed, and the test is exact

Week 2 left this open and measured: children attached at a *fraction* along
their parent, so the attachment point travelled outward as the parent extended —
up to **92px (oak)** and **128px (birch)** across a growth sweep.

The growth model is now split in two:

- **`buildMature(rules, seed)`** produces the individual's permanent form. It
  does not know about growth. Attachment is an absolute arc length on that
  form, and a branch's base is therefore fixed forever.
- **`grow(mature, growth01)`** advances a single **growth front** outward from
  the root, measured in arc length. A branch exists once the front reaches its
  attachment point, and extends from there.

One rule replaces the per-branch `emergeAt` thresholds, and monotonic growth
becomes true by construction rather than by tuning.

| Measurement, 60 seeds × 100 growth steps | Week 2 | Now |
|---|---|---|
| Worst branch slide, oak | 92 px | **0.0** |
| Worst branch slide, birch | 128 px | **0.0** |
| Worst structural shrinkage, oak | 106 px | **0.000** |
| Worst structural shrinkage, birch | 147 px | **0.000** |

The regression test asserts **exact equality** (`< 1e-9`) on base position, and
a second test asserts that every spine point of a branch is unchanged as it
extends — growth reveals a prefix, it does not rescale. The skipped test is
gone; nothing is bounded at a measured tolerance.

The split also pays for itself at runtime: `buildMature` costs 382 µs and runs
once per individual; `grow` costs 283 µs and runs only when growth changes
meaningfully.

## 2. Atlas batching, in the architecture rather than deferred

The canopy is one `drawAtlas` call per tree. Each foliage cluster contributes
three overlapping sprites; per-sprite `colors` with `BlendMode.modulate` against
luminance-only tiles means **the health uniforms still drive every pixel of
colour**. The sprite supplies shape and shading; the simulation supplies the hue.

Measured, full-maturity oak (364 branches, 324 clusters):

| Tier | Unbatched | Batched | |
|---|---|---|---|
| low | 7.37 ms | **1.68 ms** | 4.4× |
| medium | 5.58 ms | **2.69 ms** | 2.1× |
| high | 7.34 ms | **2.35 ms** | 3.1× |

Five mature trees at high quality now cost ~11.8 ms of the 16.6 ms frame budget,
against ~37 ms unbatched. The unbatched path is kept as a correctness fallback
and for tuning without an atlas loaded.

## 3. The canopy atlas — placeholder, real pipeline

`CanopyAtlasBaker` bakes a 3×2 grid of 256px tiles offline, ~640 leaf shapes per
tile with an irregular multi-lobe envelope, self-shading, a consistent
upper-left light direction, and leaves breaking the silhouette so the edge reads
leafy rather than cut out.

Baking offline buys density that is impossible per frame: several hundred shapes
per tile, against a runtime budget of a few dozen draws for a whole tree.

**These tiles are placeholders.** The runtime contract — square, luminance-only,
tinted at draw time — is what an artist's replacements must satisfy, and it is
unchanged by swapping them. The spec is in [18 §the recommendation](18-week-2-art-review.md).

Two things learned while baking:

- **Tiles must be bright and low-contrast.** They are multiplied by the leaf
  tint, so a dark baked interior darkens twice and the canopy reads as holes.
- **One sprite per cluster reads as a row of separate spheres.** Three smaller
  overlapping sprites, anchored on leaf positions the cluster already computed,
  is what merges the canopy into a single crown.

## 4. Validation — one species, every axis

| Sheet | Shows |
|---|---|
| `v_growth_ladder.png` | Eight growth values at a shared scale |
| `v_growth_continuity.png` | 2% steps across a branch emergence — nothing jumps |
| `v_health_states.png` | Thriving, thirsty, overwatered, starved, overfed, flowering, ailing, recovering |
| `v_individuals.png` | Eight individuals from one parameter set |
| `v_wind.png` | One gust sampled 0.4 s apart |
| `hybrid_hero.png` | The tree at the size it is judged at |
| `atlas_canopy_oak.png` | The baked tiles themselves |

Against *would a stranger care about this tree?* — **yes, with placeholder art.**
The crown reads as a single lit mass with depth, the trunk holds it, every
condition is legible without a legend, individuals differ, and the wind is calm
rather than busy. An artist replacing the tiles lifts it further; the pipeline no
longer stands in the way.

## 5. Skeleton tuning this week

`lengthDecay` 0.79 → 0.745 and `firstNodeAt` 0.32 → 0.37 pulled the crown in;
at 0.79 the outer branches reached far enough from the crown to leave a gap
between lobes. `asymmetry` 0.24 → 0.14 — some lopsidedness is true to an oak,
that much was leaving holes.

## 6. Scope held

Oak only. The birch atlas entry is commented out in the baking tool rather than
deleted, so adding it later is one line and not a rediscovery of the pipeline.
No new species, no new content, per the standing instruction that one
production-quality tree comes before any breadth.

## 7. Next

- Replace placeholder tiles with commissioned art (blocked on an artist).
- Wire the renderer to `grow_sim` state so `FoliageState` is derived from real
  vitals rather than passed in by hand.
- Ground, sky and weather layers; the world scene rather than one tree.
- The accessibility semantics tree, alongside the world as it is built.
