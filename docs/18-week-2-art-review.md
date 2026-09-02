# 18 — Week 2 Art Review: the R1 go/no-go

**Date:** 2026-09-02 · **Decision required by:** [ADR-0002](adr/0002-procedural-trees.md)

The question, in the terms it was set: *would a stranger care about this tree?*

Evidence is in [`docs/art-review/`](art-review/), rendered through the shipping
Canvas pipeline — not a mockup.

---

## Verdict

**GO on the procedural skeleton. NO-GO on procedural foliage as final art.**

Take the pre-approved hybrid: keep the generated branch structure, replace the
scattered leaf primitives with hand-drawn canopy masses tinted by the health
uniforms that already work.

---

## What passed, and convincingly

### Condition reads without a legend — `health_oak.png`

Six states on the same tree: thriving, thirsty, overwatered, starved, overfed,
flowering. Every one is distinguishable at a glance. The overwatered tree has
visibly saturated soil and standing water; the starved one is chlorotic yellow;
the overfed one is scorched brown.

This is the brief's section 10 requirement, met — and it is the strongest
argument for the whole approach, because **none of it is art**. Each state is a
`double` in `[0,1]` lerped from simulation state into a colour and a droop
offset. Adding seasons, or a thirtieth species, costs a palette, not a drawing.

### Growth reads as growth — `stages_quercus_robur.png`

Six stages at a shared scale. The trunk thickens, the structure multiplies, the
crown fills, the silhouette changes. A stranger reading that row left to right
sees a tree growing up.

### Species are tellable apart

Oak and birch differ in silhouette from their parameters alone — branch angle,
droop, taper, light-hunger — with no separate code path.

### The trunk is genuinely good

Taper, curvature, the fork, the lit edge. It reads as wood.

---

## What failed — `hero_oak.png`

At the scale a player actually looks at a tree, the canopy does not hold up:

- **Foliage clumps at branch tips** with bare wood between, reading as pom-poms
  on sticks rather than a canopy.
- **You see through it everywhere.** No coherent crown silhouette.
- **The outline is ragged**, with stray twigs poking past the foliage.
- It reads *generated* — the repeated fork rhythm is visible.

Six tuning iterations improved it each time without converging on beautiful. The
honest read is that the remaining distance is not another parameter sweep: a
canopy's appeal comes from an artist's decisions about mass, edge and negative
space, and scattering primitives on branch tips does not reach it.

That is exactly the failure mode [R1](13-risks.md#r1--procedural-trees-look-like-programmer-art)
predicted, found in the week it was scheduled to be found, at the cost of one
week rather than one phase.

---

## Two real bugs found on the way

Both were in the growth model, both invisible in a still image, both would have
been very expensive to find later.

### The tree reshuffled instead of growing — fixed

Branch generation threaded one RNG through the whole recursion, and the step
count for a branch was derived from its *length* — which scales with growth. So
every growth increment changed how many random numbers early branches consumed
and reshaped every branch after them.

Measured across 60 seeds × 100 growth steps: the tree could **shrink by 106px**
mid-growth. Branches were not extending; the whole tree was being redrawn
differently each time.

Fixed by seeding each branch from a stable identity — its position in the tree —
rather than from a position in one shared sequence, and by fixing step count per
depth. Worst-case structural shrinkage is now **0.000px** for oak, and 9px for
birch, where it is correct (a weeping tip genuinely falls as it lengthens).

### Branches migrate along their parents — open, Week 3

Children attach at a *fraction* along their parent, so as the parent extends the
attachment point travels with it: up to **92px (oak)** and **128px (birch)** over
a full growth sweep. Botanically a branch stays where it emerged.

The fix is to attach at an absolute distance from the parent's base and derive
the fraction from the parent's current length — which also yields a better
emergence rule for free: a child appears once its parent has grown far enough to
reach it, replacing the `emergeAt` threshold.

The test for this is committed and **marked as a skipped open defect** rather
than bounded at the measured value, because a test that passes at "the branch
moved six times its own length" guards nothing.

---

## Performance, measured

Full-quality oak, 364 branches, ~3,100 leaves:

| Tier | Leaf cap | Cost per tree |
|---|---|---|
| low | 260 | 3.26 ms |
| medium | 1,100 | 4.07 ms |
| high | 2,600 | 5.01 ms |

Geometry generation is ~1–3 ms and happens a few times per session, not per
frame. The per-frame cost above is **path construction**, and at five mature
trees it exceeds the 16.6 ms frame budget.

This confirms the batched atlas draw in [08 §4](08-animation.md#4-leaves-and-health)
is required, not optional. Leaves are currently individual `Path` objects; they
need to become one `drawAtlas` call per tree. The hybrid makes this easier, not
harder — a canopy sprite is already an atlas quad.

---

## The recommendation, concretely

Keep: skeleton generation, growth model, wind field, `FoliageState` uniforms,
palette system, species parameters, Tree Lab.

Replace: `_paintCanopy`'s per-leaf primitives with **canopy mass sprites** placed
at the existing cluster anchors, scaled and rotated per anchor, tinted by the
same uniforms.

Everything [ADR-0002](adr/0002-procedural-trees.md) claimed still holds:

| Claim | Under the hybrid |
|---|---|
| Continuous growth | Skeleton scales; sprites scale and fade with cluster radius |
| Per-tree variety | Skeleton varies; sprite choice, rotation and scale vary per anchor |
| Health as uniforms | Unchanged — tint the sprite, exactly as proven in `health_oak.png` |
| Content scaling | A species needs a palette and a handful of sprites, not 8,400 drawings |
| Small assets | A few hundred KB per species |

### Art specification, ready to commission

This is the blocker: it needs a 2D artist. The spec:

- **Canopy masses:** 5–6 per species, 256×256 PNG, premultiplied alpha, drawn as
  greyscale luminance so they can be tinted at runtime. Irregular, non-circular
  outlines with real negative space and a few leaves breaking the edge. Varying
  in shape so repetition across a canopy is not visible.
- **Leaf accents:** 3–4 individual leaves per species, 64×64, for the silhouette
  edge and for falling-leaf particles.
- **Bark texture:** one tileable 128×512 strip per species, luminance only.
- **Anchor convention:** sprite centre = cluster anchor; nominal radius = cluster
  radius; the renderer supplies scale, rotation and tint.

Two species for the MVP: Pedunculate Oak and Silver Birch. Estimated one
week of a 2D artist's time, and it is on the critical path for Week 3.

---

## Reviewing the evidence

```
docs/art-review/stages_quercus_robur.png   growth, shared scale
docs/art-review/health_oak.png             six conditions
docs/art-review/hero_oak.png               the tree at the size it is judged at
```

Regenerate with:

```
cd packages/grow_render && flutter test test/export_sheet_test.dart
```

Tune with Tree Lab — every parameter on a slider, live:

```
flutter run -t tools/tree_lab/lib/main.dart
```
