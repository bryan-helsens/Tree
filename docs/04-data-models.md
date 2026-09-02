# 04 — Core Data Models

All domain types are immutable with `const` constructors.

> **Corrected in implementation.** `grow_domain` uses **hand-written**
> immutable classes, not `freezed`. The sketches below say `freezed`, but
> [03](03-project-structure.md) requires `grow_domain` to have *zero*
> dependencies, and that is the more load-bearing rule: it keeps the simulation
> buildable anywhere with no codegen step. `freezed` remains the right choice
> for app-layer state, where classes are wider and codegen earns its keep.
> See [17 §4](17-phase-1-week-1-report.md).

## 1. Value objects

```dart
/// Simulation time: milliseconds since the save was created. Never wall clock.
extension type const SimTime(int ms) implements Comparable<SimTime> { ... }

/// 0..100, clamped on construction. Prevents the entire class of
/// "health went to 103 and the bar overflowed" bugs.
extension type const Vital._(double value) {
  factory Vital(double v) => Vital._(v.clamp(0, 100));
}

extension type const SpeciesId(String raw) {}
extension type const TreeId(String raw) {}
extension type const Seed(int raw) {}      // deterministic RNG seed
```

## 2. Content model (read-only, ships in the app bundle)

Content is **data, not code**. Adding the 40th species must not touch `grow_sim`.

```dart
@freezed
class TreeSpecies with _$TreeSpecies {
  const factory TreeSpecies({
    required SpeciesId id,
    required String nameKey,              // i18n key, not a literal
    required String scientificName,
    required Rarity rarity,               // common|uncommon|rare|veryRare|mythic
    required Family family,               // used for ecosystem diversity scoring
    required BiomeId nativeBiome,

    // --- comfort bands -------------------------------------------------
    required Band water,                  // {min, max, tolLow, tolHigh}
    required Band nutrition,
    required Band light,
    required Band temperature,

    // --- rates ---------------------------------------------------------
    required double waterUse,             // multiplier, 1.0 = baseline
    required double nutrientUse,
    required double growthRate,           // multiplier on stage durations
    required IList<double> stageHours,    // perfect-care hours per stage
    required double absorption,           // % moisture per Water unit, base 11
    required double vigor,                // healing speed multiplier
    required double resilience,           // 0..1, reduces harm rate

    // --- ecology -------------------------------------------------------
    required double animalAttraction,     // 0..2
    required double floweringChance,
    required IList<AnimalId> attracts,
    required double pestResistance,       // 0..1
    required double diseaseResistance,

    // --- discovery -----------------------------------------------------
    required IList<TraitId> traits,       // some hidden until discovered
    required double mutationChance,       // rare visual variant
    required IList<SpeciesId> mutations,

    // --- presentation --------------------------------------------------
    required BranchRules branchRules,     // procedural geometry parameters
    required LeafStyle leafStyle,         // atlas index, palette, density curve
    required SeasonalPalette palette,
  }) = _TreeSpecies;
}

@freezed
class Band with _$Band {
  const factory Band({
    required double min,
    required double max,
    required double tolLow,               // how far below min before comfort = 0
    required double tolHigh,              // how far above max before comfort = 0
  }) = _Band;
}
```

`BranchRules` is the procedural-generation contract — see
[08 §2](08-animation.md#2-tree-geometry):

```dart
@freezed
class BranchRules with _$BranchRules {
  const factory BranchRules({
    required int maxDepth,                // recursion depth at full growth
    required double trunkLengthAtMaturity,
    required double taper,                // child width / parent width
    required double lengthDecay,          // child length / parent length
    required Range branchAngle,           // degrees, per side
    required Range angleJitter,
    required int childrenPerNode,
    required double phototropism,         // 0..1 upward bias
    required double gravityDroop,         // downward bias on long thin branches
    required double asymmetry,
    required Range canopyRadius,
  }) = _BranchRules;
}
```

Animals and biomes follow the same shape:

```dart
@freezed
class AnimalSpecies with _$AnimalSpecies {
  const factory AnimalSpecies({
    required AnimalId id,
    required String nameKey,
    required Rarity rarity,
    required IList<SpawnCondition> spawnConditions,
    required TimeWindow activeHours,      // dawn/day/dusk/night
    required IList<WeatherKind> weatherAllowed,
    required BehaviourProfile behaviour,  // perchOnBranch, flitBetweenFlowers, …
    required String riveArtboard,
    required Duration minVisit,
    required Duration maxVisit,
  }) = _AnimalSpecies;
}

@freezed
class SpawnCondition with _$SpawnCondition {
  const factory SpawnCondition.treeStageAtLeast(GrowthStage stage) = _StageCond;
  const factory SpawnCondition.healthAtLeast(double health) = _HealthCond;
  const factory SpawnCondition.floweringTreesAtLeast(int count) = _FlowerCond;
  const factory SpawnCondition.speciesPresent(SpeciesId id) = _SpeciesCond;
  const factory SpawnCondition.ecosystemScoreAtLeast(double score) = _EcoCond;
  const factory SpawnCondition.diversityAtLeast(int distinctFamilies) = _DivCond;
}
```

Content JSON is validated at build time by `tools/content_lint`, which also
verifies every referenced Rive artboard, atlas index and i18n key exists. A
content error fails the build, never the runtime.

## 3. Save model (mutable game state)

```dart
@freezed
class GameState with _$GameState {
  const factory GameState({
    required Seed worldSeed,              // fixed at first launch; drives all RNG
    required SimTime simTime,             // monotonic, never decreases
    required Player player,
    required IList<Plot> plots,
    required IList<Tree> trees,
    required Inventory inventory,
    required Codex codex,                 // what has been discovered
    required Progression progression,     // streaks, challenges, stats
    required WorldConditions conditions,  // weather, season, timeOfDay
    required Settings settings,
    required Integrity integrity,         // anti-cheat bookkeeping
  }) = _GameState;
}

@freezed
class Tree with _$Tree {
  const factory Tree({
    required TreeId id,
    required SpeciesId species,
    required Seed seed,                   // fixes this individual's geometry forever
    required PlotSlotId slot,

    // vitals
    required Vital health,
    required Vital water,
    required Vital nutrition,
    required Vital growth,                // 0..100 within current stage
    required GrowthStage stage,
    required HealthState state,

    // history
    required SimTime plantedAt,
    required SimTime lastTendedAt,
    required double criticalHours,        // accumulator gating death
    required int criticalSightings,       // times the player saw it critical
    required int timesWatered,
    required int timesFed,

    // discovered knowledge — drives what the UI is allowed to reveal
    required ISet<TraitId> discoveredTraits,
    required bool waterBandKnown,
    required bool nutritionBandKnown,

    // transient visual state, derived but persisted for continuity
    required IList<Affliction> afflictions,  // pest, fungus, nutrientBurn, …
    required bool isFlowering,
    required SpeciesId? mutation,
  }) = _Tree;
}

enum GrowthStage { seed, sprout, seedling, sapling, young, mature, ancient }

enum HealthState { thriving, healthy, stressed, ailing, critical, dormant, snag }
```

Note `snag`: a dead tree becomes standing deadwood rather than disappearing. It
still hosts woodpeckers and beetles, still counts for ecosystem diversity at a
reduced weight, and yields Heartwood Seeds. This is both ecologically true and
the softest possible failure state — see [05 §6](05-simulation.md#6-health-states-and-death).

```dart
@freezed
class Inventory with _$Inventory {
  const factory Inventory({
    required int water,      required int waterCap,
    required int nutrients,  required int nutrientCap,
    required IMap<SpeciesId, int> seeds,
    required IMap<ItemId, int> items,        // decorations, rare items
    required int dewAccrued,                 // passive trickle, cap 5
    required SimTime lastDewAt,
  }) = _Inventory;
}

@freezed
class Progression with _$Progression {
  const factory Progression({
    required int level,
    required int xp,
    required int focusStreakDays,
    required int longestStreak,
    required int streakShields,              // grace tokens, max 1
    required SimTime lastStreakDay,
    required IList<Challenge> dailyChallenges,
    required IList<Challenge> weeklyChallenges,
    required IMap<int, bool> unlocksClaimed,
    required DailyStats today,
  }) = _Progression;
}

@freezed
class DailyStats with _$DailyStats {
  const factory DailyStats({
    required int dayIndex,                   // days since worldSeed epoch, local tz
    required int focusSessionsCompleted,
    required int focusMinutes,
    required int growthPointsEarned,         // for the daily soft cap
    required int notificationsSent,
    required bool deepFocusBonusUsed,
  }) = _DailyStats;
}
```

## 4. Screen-time model

Deliberately tiny. This is the *entire* set of screen-time-derived data the app
is capable of holding:

```dart
@freezed
class ScreenTimeDay with _$ScreenTimeDay {
  const factory ScreenTimeDay({
    required int dayIndex,
    required int screenOnMinutes,   // aggregate only; -1 = unavailable
    required bool underDailyGoal,   // iOS: the single bit we can learn
  }) = _ScreenTimeDay;
}
```

Retention: **14 days, rolling.** Older rows are deleted, not archived. There is
no per-app dimension anywhere in the schema, which makes the privacy claim
structurally true rather than a policy promise
([ADR-0004](adr/0004-aggregate-only-screen-time.md)).

## 5. Focus session model

```dart
@freezed
class FocusSession with _$FocusSession {
  const factory FocusSession({
    required String id,
    required Duration planned,
    required SimTime startedAt,
    required int startMonotonicMs,          // anti-cheat anchor
    required String bootId,
    required FocusMode mode,                // gentle | grounded | sanctuary
    required SessionOutcome? outcome,
  }) = _FocusSession;
}

@freezed
class SessionOutcome with _$SessionOutcome {
  const factory SessionOutcome({
    required Duration actual,
    required double integrity,              // 0.35..1.0, never 0 — Charter C2
    required int growthPoints,
    required int waterAwarded,
    required int nutrientsAwarded,
    required int xpAwarded,
    required SpeciesId? seedAwarded,
    required bool deepFocusBonus,
  }) = _SessionOutcome;
}
```

## 6. Why content and save are separate

The save stores `SpeciesId`, never the species' stats. When we rebalance an Oak
in version 1.3, every existing Oak in every player's save gets the new balance
automatically, and no migration is written. The save also records
`contentVersion` so that if a species is ever *removed*, the loader can
substitute a stand-in rather than crash.

This is the single most important schema decision for long-term content
velocity, and it is why [C8](00-design-charter.md) can promise post-launch
content without a live-ops backend.
