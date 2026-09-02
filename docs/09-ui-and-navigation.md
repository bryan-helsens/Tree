# 09 — UI & Navigation Architecture

## 1. Navigation

`go_router` with a `StatefulShellRoute` — four persistent branches, each keeping
its own navigation stack.

```
/forest        (default)   the living world + HUD          🌳
/focus                     session picker / running / done ⏳
/satchel                   inventory                       🧺
/guide                     field guide (discoveries)       📖

  modal / pushed
  /forest/tree/:id         draggable bottom sheet over the live world
  /welcome-back            full-screen, on resume when elapsed > 20 min
  /onboarding              first run
  /settings                pushed from HUD
  /levelup/:n              overlay route
```

The world screen is `/forest` and it is also home; there is no separate home
screen, because the forest *is* the thing. Level and XP live in a translucent top
bar over the world, not on a stats page.

**Focus gets a tab of its own** because it is the product's hook. Burying the
central mechanic in a menu would be a design error.

## 2. The world stays visible

The tree detail panel is a **draggable bottom sheet at 45% height**, not a
full-screen route. The tree stays on screen above it, still animating, still
reacting when you water it. The brief's target feeling — *"a beautiful digital
terrarium"* — depends on never cutting away from the terrarium.

The Flame `GameWidget` is mounted once, at the shell level, and persists across
tab switches. Tabs are overlays and side panels, not replacements. Switching to
the Satchel slides a panel over a still-running world.

## 3. Screen inventory (MVP)

| Screen | Purpose | Notes |
|---|---|---|
| Onboarding | plant the first seed | 4 steps, no account, no permissions requested |
| Forest | the world | HUD: level+XP, 💧, 🌱, streak, settings |
| Tree detail sheet | stats + actions | see §4 |
| Focus picker | choose a duration | 10/20/30/45/60/custom; mode selector if capable |
| Focus running | timer | huge, calm, dimmable; "put the phone down" is the CTA |
| Focus complete | reward reveal | growth injection animation is the hero moment |
| Satchel | inventory | four sections, no tabs |
| Field Guide | discoveries | silhouettes for undiscovered species |
| Progression | level, challenges, streak | reached from the HUD level chip |
| Welcome Back | offline summary | animated sequence, skippable |
| Settings | audio, motion, notifications, privacy, data | privacy is a top-level section |

## 4. Tree detail panel

```
┌────────────────────────────────────────────┐
│  ▁▁▁▁                                      │
│  SILVER BIRCH              Uncommon ✧✧     │
│  Sapling · 3 days old                      │
│                                            │
│  ●  Healthy                                │  ← glyph + word + colour (C6)
│                                            │
│  ❤️  Health      ▓▓▓▓▓▓▓▓▓░  94            │
│  💧  Water       ▓▓▓▓▓▓░░░░  62            │
│      ideal 45–70  ├────▓▓▓▓▓▓──────┤       │  ← band shown ON the bar
│  🌱  Nutrition   ▓▓▓▓▓░░░░░  54            │
│      ideal 40–65  ├───▓▓▓▓▓▓───────┤       │
│  🌿  Growth      ▓▓▓▓▓▓▓░░░  72            │
│                                            │
│  Traits   Fast grower · ?????? · ??????    │  ← undiscovered stay hidden
│                                            │
│  ┌──────────────┐  ┌──────────────┐        │
│  │  💧 Water    │  │  🌱 Feed     │        │
│  │  +11 → 73    │  │  +22 → 76 ⚠  │        │
│  └──────────────┘  └──────────────┘        │
└────────────────────────────────────────────┘
```

Three UI decisions that carry design weight:

1. **The ideal band is drawn on the bar itself**, not written underneath. The
   player sees the target as a region and their value as a position in it. This is
   how the water/nutrient strategy becomes readable without a tutorial.
2. **The action button previews its result** — `+22 → 76 ⚠` — and warns when the
   result would leave the safe band. It warns; it does not block. Per the brief,
   the player must be allowed to make the mistake, because making it is how the
   system teaches.
3. **Undiscovered traits render as `??????`**, so the panel doubles as a
   collection surface and gives the player a reason to keep a tree long enough to
   learn it.

## 5. State management

Riverpod with code generation.

```
gameStateProvider          AsyncNotifier<GameState>     single source of truth
worldSnapshotProvider      Provider<WorldSnapshot>      render projection
treeProvider(TreeId)       Provider<Tree>               .select-friendly
inventoryProvider          Provider<Inventory>
focusSessionProvider       Notifier<FocusSessionState>  the session state machine
capabilitiesProvider       FutureProvider<ScreenTimeCapabilities>
```

Rules:
- Widgets use `ref.watch(p.select(...))` — never a whole `GameState` in a leaf.
- All mutations go through use cases (`WaterTree`, `FeedTree`, `CompleteSession`)
  that return `Result<GameState, GrowError>`. Widgets never construct state.
- The Flame world subscribes to `worldSnapshotProvider` **once** and diffs; it
  does not rebuild a widget tree per frame.

## 6. Design system

Tokens only. No literal colour, spacing, radius, duration or curve anywhere
outside `design_system/tokens/`, enforced by a custom lint.

**Palette direction:** desaturated naturals — moss, bark, clay, overcast sky, warm
sand — with exactly one accent (a soft gold used for discovery and level-up and
nothing else). Deep greens and near-blacks for night. Explicitly avoided: neon,
heavy gradients, drop shadows on everything, cartoon outlines, the generic
farming-game palette.

**Type:** one humanist sans for UI, one high-contrast serif for species names and
discovery cards — the serif is what makes the field guide feel like a botanical
reference rather than a loot screen.

**Depth** comes from atmospheric perspective (distant layers desaturate and
lighten) rather than from shadows and borders.

The UI is themed by time of day and season: the same widgets pull from a palette
resolved at runtime, so the interface warms at dusk along with the world.

## 7. Accessibility

- **Semantics for the canvas world.** The Flame world is not accessible by
  default. A parallel `Semantics` tree is built from the `WorldSnapshot`, one node
  per interactive tree, labelled *"Silver Birch, sapling, healthy, water 62 of an
  ideal 45 to 70. Double tap to open."* This is non-negotiable and is a Phase 1
  task, not a Phase 5 one — retrofitting it is far more expensive.
- **Never colour alone** (Charter C6): every health state has a glyph, a word, and
  a silhouette change.
- **Dynamic type** honoured to 200%; layouts tested at 320 dp width × 200% scale.
  No fixed-height text containers.
- **Contrast** ≥ 4.5:1 for body text, ≥ 3:1 for large text and meaningful icons,
  verified by a golden test that samples rendered pixels.
- **Reduced motion** per [08 §8](08-animation.md#8-reduced-motion).
- **Haptics toggle**, default on, with distinct light/medium/heavy patterns
  mapped to action classes.
- **Touch targets** ≥ 48 dp; trees get an expanded hit region that never falls
  below 48 dp regardless of growth stage.
- **Timers** are pausable and extendable; no time-limited interaction anywhere in
  the game.

## 8. Localisation

All player-facing strings are ARB keys from day one, including the ones in
content JSON (`nameKey`, not `name`). MVP ships English only, but retrofitting
i18n after content exists is one of the classic avoidable rewrites.
