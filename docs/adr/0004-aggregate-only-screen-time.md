# ADR-0004 — The app never learns which apps the player uses

**Status:** proposed · **Date:** 2026-09-02

## Context

Android's `PACKAGE_USAGE_STATS` grants full per-app foreground-time statistics.
The obvious feature ("you spent 2 h in social media") is available and would be a
standard thing to build.

## Decision

We read **only** `SCREEN_INTERACTIVE` / `SCREEN_NON_INTERACTIVE` transitions to
compute aggregate screen-on time. No package names are read, resolved, stored or
displayed. `QUERY_ALL_PACKAGES` is not declared. The `ScreenTimeDay` schema holds
two integers and a boolean, with a 14-day rolling retention.

## Rationale

1. **Structural rather than promissory privacy.** A schema with no per-app
   dimension cannot leak per-app data, whatever a future feature request says.
   That is a stronger guarantee than a policy document.
2. The game does not need it. Rewards depend on *how much*, never on *what*.
3. It removes package-visibility complexity and shrinks the Play data-safety
   declaration to something we can defend in one sentence.
4. iOS structurally cannot provide per-app data anyway, so building the feature
   would create a permanent, visible asymmetry for no gameplay gain.

## Consequences

**Positive** — a privacy claim that is true by construction; a smaller policy
surface; genuine platform symmetry in what the game *knows*.

**Negative** — no category-level insights ("you cut social media by 20%"), which
some competitors offer. Accepted, and stated plainly in the UI rather than
apologised for.
