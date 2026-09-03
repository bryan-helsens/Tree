# 24 — Phase 1, Week 7: the focus session experience

The state machine got a face. Also: the persistence decision you asked for,
and the Week 5 ghost turned out to be real and trivial.

## 1. The persistence decision — option B, made enforceable

**JSON is the pre-release save format. Drift is the release format. The
boundary is the first build handed to anyone outside the team.**

Recorded as [ADR-0005](adr/0005-json-save-format.md), which also carries the
cutover plan and the checklist that must be green before a first release.

The part that matters is that this is not a promise:

| Piece | What it does |
| --- | --- |
| `SaveFormat.version` | What this build writes. |
| `SaveFormat.migrations` | `n → n+1` steps. Empty at v1, correctly. |
| `SaveFormat.released` | **The boundary, as data.** Every version ever shipped. |
| `save_format_test.dart` | Fails the build if a released version loses its path. |

While `released` is empty the format is private and may change freely — dev
saves can be reset, because everyone holding one can be told. Adding to that
set *is* the act of shipping, and from that moment every change owes a
migration. There is also a tripwire test asserting the format is still private;
when someone ships, it fails and points at the ADR.

Not Drift now, because the three things the normalised schema buys — partial
writes, field-guide queries, sync-readiness — have no consumer yet, while the
schema would be rewritten several times over a domain that has changed every
week. And because the atomicity the game actually depends on is *stronger* with
one document: the reward and the `claimed` phase are fields of the same object,
so exactly-once needs no transaction. Under Drift that becomes a transaction
that has to be correct.

docs/10 now opens by saying it is a specification rather than a description.

## 2. The focus experience

Four surfaces, all pure functions of one projection.

`FocusView.of(GameState)` reads the save and says what belongs on screen:
`FocusIdle`, `FocusRunning`, `FocusSettling`, `FocusFinished`. Widgets render
it. **No widget knows whether a session is running** — it asks. The only local
state in the whole feature is the duration a player is scrolling through before
they commit, which is not a session until they say so, and whether a sheet is
open.

- **Picker.** Four durations, and what each pays before committing to it —
  two numbers, not a table. The economy is pure, so this is the real yield.
- **Running.** A filling ring, minutes rounded up, and the sentence that
  matters: *"You can close the app. The session keeps its own time."* Never a
  per-second countdown — that is the version of this screen that asks to be
  watched. Finishing early is offered quietly and phrased as what it is:
  *"you keep what you have earned."*
- **Completion.** At most three figures: water, feed, growth. No XP, no growth
  points, no streak fanfare — those live in the HUD and can be noticed rather
  than announced. A fully grown tree is told the truth instead of being shown
  a zero.
- **Welcome back.** Below.

Wired up: the HUD call opens the picker, `ForestScreen` now calls `resume()`
on first frame and `onPaused()` on backgrounding, and the repository and clock
are injectable providers — so tests drive the shipping path, and a device build
swaps in file storage with no other change.

## 3. The welcome-back moment

The target feeling was *"I was away, and something happened"*, not *"you
completed another productivity task"*. Three rules came out of that, and they
are why the screen looks the way it does:

1. **The world speaks first.** The journal's own sentences lead — *"Pedunculate
   Oak became a young tree"*. Resources come last, under a rule, small.
2. **Time is described, not measured.** `ReturnSummary.awayInWords` gives
   "a few hours", never "187 minutes". A number here is a stopwatch, and a
   stopwatch is the thing this product exists to get away from.
3. **Nothing is claimed here.** The reward was committed during `resume()`,
   possibly before this widget existed.

One fix behind it: `highlights` took the first four journal entries
chronologically, so a two-day absence showed four rain showers and pushed the
stage-up off the end. It now ranks by `SimEvent.significance` and takes three.

## 4. Growth had to stop popping

The reward lands as a step change in `tree.growth`. Drawing that step directly
makes the tree pop, which reads as a slot machine paying out — the opposite of
attachment. The screen now eases *drawn* size toward the domain's, exactly as
it already eased foliage. The domain value stays the truth; only its display
lags, and more slowly than foliage, so a tree looks like it is growing rather
than inflating.

Writing the test for it found a real bug in my own first version: the seed
happened lazily inside the easing loop, *after* the frame-time guard. A tree
first seen on a skipped frame got seeded later, from a target that had since
moved — and snapped to it. Seeding now happens before the guard.

Worth noting honestly: at a single session's reward the growth step is small
enough that it barely pops anyway. The easing earns its keep on returns from a
long absence, which is exactly where the tree changes most.

## 5. The Week 5 ghost was real, and it was a `const`

The "ghost focus call rendering behind the open sheet" was not a rendering
artifact. `ForestHud.showCall` was declared, documented — *"Hidden while a tree
panel is open, so there is only ever one primary action on screen"* — and
**never read**. The call rendered underneath every sheet, exactly as reported.

Found by writing a test that asserted the documented behaviour, not by looking
at a screenshot. One line to fix, with a regression test that checks there is
no copy inside the `ForestHud` subtree while a sheet is open.

A parameter that does nothing is worse than a missing one: it reads as a
decision that was made.

## 6. Tests

All nine required scenarios are covered. New this week in **bold**.

| Requirement | Where |
| --- | --- |
| start → persist → kill → relaunch → session exists | `session_recovery_test` |
| completed → committed → kill → relaunch → no duplicate | `session_recovery_test` |
| completion without tapping anything | `session_recovery_test`, **`focus_ui_test`** |
| interrupted session | `session_recovery_test`, **`focus_ui_test`** |
| clock anomaly | `clock_guard_test`, `session_recovery_test` |
| offline elapsed time | `session_recovery_test`, **`focus_flow_test`** |
| **multiple resume calls** | **`session_recovery_test`** |
| **exactly one growth transaction** | **`session_recovery_test`** |
| **fully grown tree, no phantom progression** | **`session_recovery_test`**, **`focus_ui_test`** |

Plus the projection itself: `FocusView` derivation, minutes rounded up not
down, the picker starting a session through the controller rather than itself,
the welcome-back screen leading with the world, significance outranking
weather, and no XP leaking onto the return screen.

52 app tests, up from 28.

## 7. Gate

| Check | Result |
| --- | --- |
| `dart analyze` (workspace) | clean |
| `arch_check` | all boundaries hold — **and now scans `apps/`** |
| `grow_domain` / `grow_content` / `grow_sim` / `grow_flora` / `grow_data` | pass |
| `grow_render` (4 files, incl. golden sheets and bench) | pass |
| `grow_app` (52 tests across 4 files) | pass |
| balance ship criteria | 7/7, unchanged |

**`arch_check` was never scanning `apps/`.** The scan looped over `packages`
and `tools` only, so `grow_app` — the one package that composes the whole stack,
and where a boundary is easiest to cross by accident — had rules declared and
never enforced. It scans `apps` now, `grow_app` is allowed Flutter, and
`DateTime.now()` is permitted in exactly one named file
(`time_authority.dart`), by an allowlist rather than a package-wide exemption.
Verified the guard actually bites by planting a violation and watching it fail.

The screenshot test still hangs in this container, and still hangs identically
at the Week 5 commit. Recorded, not chased. CI runs the four fast app suites.

## 8. Balance — unchanged, as instructed

Numbers untouched. The three-archetype comparison you described — no sessions,
one daily session, several daily sessions, judged on whether *"I put my phone
down, and that helped my tree"* is legible rather than merely true — is the
right next experiment now that the surfaces exist. It wants the commissioned
canopy art first: with the placeholder atlas, "emotionally visible" is not
something the harness or I can honestly judge.

## 9. Next

1. The three-archetype legibility comparison, once there is art worth judging.
2. Commissioned canopy art — still the open Week 5/6 quality gate.
3. Device storage: a file-backed `SaveRepository` behind the provider that is
   already there, whenever there is a platform to run on.
