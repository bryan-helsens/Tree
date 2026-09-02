# ADR-0002 — Procedural tree generation over sprite growth stages

**Status:** proposed · **Date:** 2026-09-02

## Context

The brief requires visible continuous growth, per-species silhouettes, five
distinct health appearances, seasonal change, flowering states, and eventually
dozens of species — with nothing looking like a static PNG.

## Decision

A tree is a deterministic function of `(species.branchRules, treeSeed, growth01)`,
producing a branch skeleton and leaf-cluster anchors rendered with instanced
quads and animated by a shared wind field.

## Rationale

The sprite alternative does not survive its own asset count:
`7 stages × 5 health states × 4 seasons × 2 flowering × 30 species ≈ 8,400`
hand-drawn trees — and growth would still *pop* between stages while every tree
of a species stayed identical.

Procedural generation makes growth genuinely continuous, gives every individual
tree its own shape, turns health into shader uniforms rather than art, and
reduces the asset budget to kilobytes.

## Consequences

**Positive** — continuous growth; free variety; health/season/flowering as
parameters; trivial content scaling.

**Negative and serious** — "procedural" and "beautiful" are far apart, and this
is the project's top risk ([13 R1](../13-risks.md#r1--procedural-trees-look-like-programmer-art)).

**Mitigations** — `tools/tree_lab` as a week-2 deliverable; professional leaf
atlas and palette commissioned early; a **week-2 art go/no-go**; and a designed
fallback (hand-drawn canopy sprites on a procedural branch skeleton) that
preserves continuous growth and per-tree variety while restoring art control.
