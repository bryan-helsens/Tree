# 00 — Design Charter

These are product constraints with engineering teeth. Each one has a mechanical
consequence elsewhere in this architecture. A pull request that violates one of
these is rejected regardless of how well it is written.

## C1 — Ignoring the game is never punished

The game's entire proposition is "spend less time on your phone." If a two-week
absence killed a forest, the game would be asking the player to check it daily,
which is the behaviour it claims to discourage.

**Mechanical consequence:** after 72 simulated hours offline, trees enter
**Dormancy**: vitals asymptote toward a resting equilibrium and health decays at
a quarter rate with a hard floor of 15. A tree can never die from absence alone —
only from sustained neglect *while the player is actively playing*
(see [05 §6](05-simulation.md#6-health-states-and-death)).

## C2 — No fail states on focus sessions

A focus session that "fails" teaches the player that the app is a judge.

**Mechanical consequence:** session integrity produces a multiplier in
`[0.35, 1.0]`, never zero, and never the word "failed."
See [ADR-0003](adr/0003-soft-enforcement.md).

## C3 — The game never learns which apps you use

Not "doesn't upload." Does not *collect*.

**Mechanical consequence:** Android reads only `SCREEN_INTERACTIVE` /
`SCREEN_NON_INTERACTIVE` events, never per-package statistics, and the app does
not declare `QUERY_ALL_PACKAGES`. iOS is structurally incapable of it anyway.
See [ADR-0004](adr/0004-aggregate-only-screen-time.md).

## C4 — The game is fully playable with zero permissions granted

Screen-time integration is an enhancement tier, not a gate. A player who denies
everything gets focus sessions, the full simulation, and the full progression
curve at unchanged rates.

## C5 — There is always one meaningful action available

No "come back in 8 hours" screens. Passive **Dew** accrues 1 Water per 3 hours
(cap 5) so a returning player can always act on something.

## C6 — Colour is never the only carrier of state

Every health state has a glyph, a word, and a distinct silhouette change, in
addition to colour. See [09 §7](09-ui-and-navigation.md#7-accessibility).

## C7 — Maximum two notifications per day, zero guilt language

A banned-phrase list is a compile-time constant checked by a unit test. Banned:
*losing, dying, dead, failed, missed, don't forget, hurry, last chance, streak
lost, neglected*. See [11 §4](11-notifications.md#4-copy-rules).

## C8 — No monetisation surface in the MVP

Not disabled — absent. No IAP entitlement, no store screen, no remote price
config, no ad SDK, no third-party analytics SDK.

## C9 — Audio never interrupts the player's own audio

`AVAudioSession` category `.ambient` on iOS, `AudioAttributes` usage
`USAGE_GAME` with `setAudioAttributes` honouring ducking on Android. A player
focusing to their own music must not have it stopped by a bird chirp.

## C10 — No background services in the default configuration

Everything is timestamp-based catch-up simulation. Battery cost of a closed GROW
is zero. This is both a philosophy point and the main reason the architecture
avoids continuous processes ([05 §1](05-simulation.md#1-time-model)).
