# 14 — Development Roadmap

Estimates assume **one senior developer plus a part-time 2D artist/animator**.
Scale accordingly. Every phase ends in a demoable build and a written go/no-go.

---

## Phase 0 — Planning ✅ (this document)
**Awaiting approval. No code written.**

Exit: architecture approved, or revised and re-approved.

---

## Phase 1 — Vertical slice · ~5 weeks

The one complete loop: **seed → tree → care → growth → reward → focus →
progression**, polished.

### Week 1 — Foundations and the long-lead item
- **Day 1: submit the Family Controls entitlement request.** (R2 — longest lead
  time in the project, free to start, expensive to delay.)
- Monorepo, workspace, CI, lints, `arch_check`.
- `grow_domain` entities; `grow_sim` skeleton + `TimeAuthority` plugin.
- Simulation unit tests and the determinism property test **before** any UI.

*Milestone M1: a headless 30-day simulation runs in CI and emits a CSV.*

### Week 2 — The visual bet, resolved early
- Procedural tree generator, wind field, leaf instancing.
- `tools/tree_lab` with live sliders for every parameter.
- Art: leaf atlas, bark, ground, first palette.

*Milestone M2: **art review go/no-go on R1.** An Oak at four growth stages, side
by side, judged screenshot-worthy — or we take the hybrid fallback now.*

### Week 3 — The world
- Flame scene graph, layers, camera, day/night, weather (sunny/cloudy/rain).
- Health→visual uniform mapping (droop, pallor, scorch, wetness).
- Semantics tree built alongside (R11).
- Performance gate wired into CI (R7).

*Milestone M3: a living forest that reacts to simulated state, at 60 fps on target
devices.*

### Week 4 — Interface and care
- Design system tokens, HUD, tree detail sheet with on-bar ideal ranges.
- Water/feed actions with full feedback chains.
- Drift persistence, backup rotation, migration test harness.

*Milestone M4: you can care for a tree, close the app, and come back to a correct
world.*

### Week 5 — The hook
- Focus session state machine, Gentle mode, Android Grounded mode.
- Economy, XP, levels 1–8, daily challenges, streak + shield.
- Notifications with predictive scheduling.
- Welcome Back sequence.
- Onboarding beat sheet from [12 §4](12-mvp-plan.md#4-the-first-five-minutes-scripted).

*Milestone M5: **the MVP acceptance criteria are run against 5 external
testers.** This is the real go/no-go for the whole product.*

---

## Phase 2 — Feel · ~3 weeks

Nothing new; everything better. This phase is what separates a prototype from a
product and it is routinely cut. It is not cut.

- Animation polish pass: every transition, every easing curve, every particle.
- Audio: ambient beds, wind layers keyed to the wind field, 8 SFX, ducking,
  the media-app compatibility matrix (R10).
- Haptics vocabulary.
- Balance pass driven by `tools/balance_sim` against all five archetypes.
- Accessibility audit: contrast, dynamic type at 200%, VoiceOver/TalkBack walk.
- OEM battery-management testing for alarms (R8).
- Cold start optimisation.

*Exit: a stranger uses it for a week and describes it as calm and beautiful
without prompting.*

---

## Phase 3 — Content · ~4 weeks

- Species 3–12 across common/uncommon/rare (the pipeline test from
  [12 §5](12-mvp-plan.md#5-content-pipeline-proven-in-the-mvp) applies: **JSON
  only, no Dart**).
- Animals 3–8 with full lifecycle behaviours.
- Plants, flowers, ground cover variety.
- Discovery system depth: trait revelation, mutations, the field guide as a real
  collection.
- Levels 9–15 with their mechanical unlocks.
- Decorations and the compost bin.

---

## Phase 4 — World · ~5 weeks

- Blossom Valley as the **second biome — the real test of the biome abstraction**;
  expect to refactor here, and budget for it.
- Full weather: storm, fog, snow, with genuine gameplay consequences.
- Seasons with visual and mechanical effects.
- Plot expansion and world map.
- Levels 16–20, ecosystem tier.

---

## Phase 5 — Platform · ~3 weeks
*(Started in parallel from Phase 1 day 1 for the entitlement.)*

- iOS Grounded mode once the entitlement lands; Sanctuary mode.
- Android baseline comparison and screen-time milestones.
- Widgets, Live Activities.
- Store readiness: privacy manifests, data safety declarations, screenshots,
  localisation.
- Cloud sync (the columns are already there — [10 §8](10-persistence.md#8-cloud-sync-readiness-post-mvp-explicitly-out-of-mvp-scope)).

---

## Critical path and parallelism

```
week   1   2   3   4   5   6   7   8   9  ...
       ├───┴───┴───┴───┤ Phase 1 (vertical slice)
       │   ├─ M2 art go/no-go  ← decide R1 here, not later
       │                   └─ M5 external playtest ← decide the product here
       ├──────────────────────────────────────────► Apple entitlement (async, weeks)
       ├──────────► art asset production (parallel, independent)
                       ├──────► Play internal-test build for policy check (R4)
```

The two decisions that must not slip:
1. **Week 2** — does procedural look good enough? If not, take the hybrid
   fallback immediately, while it is cheap.
2. **Week 5** — do external testers feel attachment to a tree? If not, no amount
   of Phase 3 content fixes it, and the design needs rework before scaling.

## What "done" means for Phase 1

Not "the features exist." The thirteen acceptance criteria in
[12 §3](12-mvp-plan.md#3-acceptance-criteria) pass, on real devices, with real
strangers, including the ones that are about feeling rather than function.
