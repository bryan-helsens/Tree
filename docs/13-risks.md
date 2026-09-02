# 13 — Risks & Technical Limitations

Ranked by expected cost, not by likelihood alone.

## R1 — Procedural trees look like programmer art
**Likelihood: high · Impact: fatal to the product's premise**

The entire visual identity rests on generated geometry looking beautiful. The gap
between "correct L-system" and "a tree you want to look at" is large and is closed
by hundreds of small aesthetic decisions, not by algorithm choice.

**Mitigation.** `tools/tree_lab` is a **week-2 deliverable**, not a nice-to-have.
Commission a professional leaf atlas, bark texture and seasonal palette before any
species tuning. Book an art review at the end of week 3 with a hard **go/no-go**:
if the Oak does not look good enough to screenshot, we fall back to a hybrid —
hand-drawn canopy sprites on a procedural branch skeleton — which keeps continuous
growth and per-tree variety while buying back art control. That fallback is
designed for now so it is not designed under pressure later.

## R2 — Family Controls entitlement is slow, opaque, or denied
**Likelihood: high · Impact: high on iOS feature set, zero on schedule if handled**

Approval requires a manual Apple review, needs to be requested for the app *and*
every extension separately, and developers have reported multi-week waits with no
acknowledgement.

**Mitigation.** Submit in **week 1 of Phase 1**, before writing iOS screen-time
code. iOS v1 ships Gentle mode only; Grounded and Sanctuary are flag-off features
delivered in a later release. **No launch date depends on Apple's queue.**

## R3 — iOS can never reach Android's feature parity
**Likelihood: certain · Impact: moderate, permanent**

`DeviceActivityReportExtension` is sandboxed from the host app by design. iOS
cannot report screen-time numbers, ever.

**Mitigation.** Not a bug to fix — a constraint to design around. iOS gets the
one-bit daily-goal model ([07 §3](07-screen-time-integration.md#3-baseline-comparison-youre-using-your-phone-18-less)),
and the UI is capability-driven so no iOS player is shown a feature that does not
exist. Marketing copy must not promise usage insights on iOS.

## R4 — Play Store rejects usage access for a game
**Likelihood: moderate · Impact: high if it happens late**

A reviewer may decide a game has no core need for `PACKAGE_USAGE_STATS`.

**Mitigation.** Prominent disclosure flow built to Google's stated standard;
permission gated behind a full explanation screen; app fully functional without
it. Because it is a bonus tier behind a capability flag, it can be removed in a
patch without touching the core loop. **Submit an early internal-testing build
specifically to smoke out the policy question**, well before the store listing is
finalised.

## R5 — Retention metrics will look bad by industry standards
**Likelihood: certain · Impact: strategic**

A game whose thesis is "use your phone less" will have low session length and low
DAU-minutes. Judged conventionally, it will look like it is failing while working
perfectly.

**Mitigation.** Define success up front and instrument for it: *focus sessions
completed per user per week*, *day-7 streak retention*, *total minutes of
non-phone time generated*. Deliberately do **not** optimise session length. Write
this into the store listing and any investor material so nobody re-optimises the
product into the thing it was built to replace.

## R6 — Scope. The brief describes a three-year game
**Likelihood: certain · Impact: high**

Sections 12–20 of the brief (biomes, seasons, dozens of species, complex animal
behaviour) are a multi-year content roadmap presented alongside the MVP.

**Mitigation.** [12](12-mvp-plan.md) is an explicit contract with a written OUT
list. The architecture's job is to make each of those additive; the plan's job is
to keep them out of Phase 1. Any request to pull one forward is a scope trade, not
an addition.

## R7 — Procedural rendering performance on low-end Android
**Likelihood: moderate · Impact: moderate**

Per-frame transforms over ~400 branch segments × N trees plus thousands of leaf
instances, in Dart, without SIMD.

**Mitigation.** Geometry cached and regenerated only on meaningful growth change;
`drawAtlas` batching; hard instance caps per quality tier; a startup benchmark
choosing the tier. A **CI performance gate** running the busiest scene on a
low-end device profile, failing the build on frame-time regression. This is the
first thing to profile in Phase 1, not the last.

## R8 — Notification precision on Android
**Likelihood: moderate · Impact: moderate**

Android 14+ foreground service types have no legitimate category for an idle
timer, and `SCHEDULE_EXACT_ALARM` is restricted.

**Mitigation.** `AlarmManager.setAlarmClock()` — Doze-exempt, no special grant, and
semantically correct for a user-set timer
([11 §5](11-notifications.md#5-focus-session-timing)). Verify on OEM builds with
aggressive battery management (Xiaomi, Samsung, Oppo) during Phase 2; add a
detection-and-explain path for devices that kill alarms anyway.

## R9 — Clock manipulation
**Likelihood: low · Impact: low**

A determined offline player can advance time.

**Mitigation.** Monotonic cross-check, boot-id, per-day accrual caps, and an
out-of-database high-water mark ([05 §8](05-simulation.md#8-clock-integrity)).
**Accepted residual risk:** with no server and no competitive surface, a player
who cheats only affects their own forest. Building more would violate the brief's
"do not create an invasive anti-cheat system."

## R10 — Audio interrupting the player's own media
**Likelihood: moderate if unhandled · Impact: high on trust**

Many people focus to music. An app that stops it during a focus session has
actively harmed the thing it claims to support.

**Mitigation.** `AVAudioSession.Category.ambient` on iOS, `USAGE_GAME` with proper
ducking on Android, all ambient audio off by default during a running focus
session, and a Phase 2 test matrix against Spotify, Apple Music, YouTube and a
podcast app. Charter C9.

## R11 — Canvas accessibility
**Likelihood: high if deferred · Impact: moderate**

A Flame world is invisible to screen readers by default, and retrofitting a
semantics tree after the render layer is mature is expensive.

**Mitigation.** The parallel `Semantics` tree is a **Phase 1** task
([09 §7](09-ui-and-navigation.md#7-accessibility)), built alongside the world, not
after it.

## R12 — Dependency churn
**Likelihood: moderate · Impact: low–moderate**

Flame has a history of breaking API changes; Rive's runtime moves fast.

**Mitigation.** Exact version pins, a single `dependencies.yaml`, Flame's surface
area kept small and wrapped behind `grow_render` interfaces, and golden tests that
catch rendering regressions on upgrade.

## R13 — The product paradox
**Likelihood: certain · Impact: philosophical, and it will be raised in reviews**

*"You built a phone app to make me use my phone less."*

**Mitigation.** Make it a design constraint rather than a defence. The app is a
destination with a bottom: no feed, no infinite scroll, an explicit "nothing more
to do right now, come back tomorrow" state, and a hard notification cap. GROW's
own usage is excluded from the reduction calculation and the UI says so. If a
session takes more than three minutes of screen time to be satisfying, that is a
bug in this product, and it should be tracked as one.

## Known limitations, accepted and documented

1. iOS cannot measure usage. Permanent.
2. Android cannot block apps without abusing Accessibility APIs. We will not.
3. Offline simulation caps at 72 h of active dynamics; beyond that is dormancy —
   a deliberate design choice ([Charter C1](00-design-charter.md)), not a technical
   limit.
4. No cloud sync in v1: losing the device loses the forest. Mitigated by
   sync-ready columns and prioritised immediately post-MVP.
5. Simulation uses `double`; results are reproducible on a given device but not
   guaranteed bit-identical across architectures. Acceptable for a single-player
   game, and a constraint to revisit before any server-authoritative feature.
