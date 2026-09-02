# ADR-0003 — Focus sessions use soft enforcement, never a fail state

**Status:** proposed · **Date:** 2026-09-02

## Context

Comparable apps fail a session when the user leaves the app, sometimes killing a
virtual plant. It is effective at compliance and it is exactly the shaming
dynamic the brief rules out.

There is also a technical driver: strict enforcement requires either abusing
Android's `AccessibilityService` (which risks Play removal) or depending on an
iOS entitlement whose approval we do not control.

## Decision

Session integrity is a continuous multiplier in `[0.35, 1.0]`. There is no fail
state, no zero, and the word "failed" does not appear in the product.

```
integrity = clamp(1.0 - 1.3 · max(0, usedFraction - 0.04), 0.35, 1.0)
```

Gentle mode — the default, with no permissions — awards **full** integrity.

## Rationale

Rewarding at 1.0 by default means the permission-free experience is not the
punished one. There is no leaderboard, so a player who games it affects nobody.
And it makes the entire feature degrade gracefully across a permission matrix we
do not control.

Design and engineering agree here, which is usually a sign the decision is right.

## Consequences

**Positive** — matches the product's emotional thesis; works identically on every
permission configuration; no dependency on a restricted API for the core loop.

**Negative** — weaker behavioural compliance than a punishing competitor, and
"you can just cheat" will appear in reviews. Accepted: this product's success
metric is *minutes of attention returned to the player*, not compliance.
