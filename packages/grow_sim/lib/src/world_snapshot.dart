import 'dart:math' as math;

import 'package:grow_content/grow_content.dart';
import 'package:grow_domain/grow_domain.dart';

import 'comfort.dart';
import 'sim_constants.dart';
import 'weather_oracle.dart';

/// One tree, as the renderer needs it.
class TreeVisual {
  const TreeVisual({
    required this.id,
    required this.speciesId,
    required this.seed,
    required this.slot,
    required this.growth01,
    required this.stage,
    required this.state,
    required this.foliage,
    required this.comfort,
    required this.label,
    required this.detail,
    required this.ageReference,
  });

  final TreeId id;
  final SpeciesId speciesId;
  final int seed;
  final int slot;

  /// Combined progress across the whole stage ladder, 0..1 — what the
  /// generator's growth front consumes.
  final double growth01;

  final GrowthStage stage;
  final HealthState state;
  final FoliageState foliage;
  final double comfort;

  /// Short label for the accessibility node.
  final String label;

  /// The full spoken description, built once here rather than in a widget so
  /// it is testable without pumping a frame.
  final String detail;

  /// The simulated instant this visual was taken at. The UI needs it to show
  /// an age without reading a real clock — nothing outside TimeAuthority may.
  final SimTime ageReference;
}

/// A flattened, render-oriented projection of the simulation.
///
/// The renderer consumes this and never reads domain entities directly, and it
/// never writes back. That one-way discipline is what lets the world be
/// rebuilt from a save at any time and what keeps the render layer testable.
class WorldSnapshot {
  const WorldSnapshot({
    required this.trees,
    required this.conditions,
    required this.timeOfDay01,
    required this.simTime,
    required this.biome,
  });

  final List<TreeVisual> trees;
  final WorldConditions conditions;

  /// 0 at midnight, 0.5 at midday. Drives sky, light and shadow direction.
  final double timeOfDay01;

  final SimTime simTime;
  final BiomeId biome;
}

/// Turns simulation state into appearance.
///
/// Every visual property a tree has is derived here from its vitals and its
/// species' bands. Nothing downstream invents a look: a drooping tree is
/// drooping *because* its moisture is below the band, and by exactly as much.
class WorldProjector {
  const WorldProjector({
    required this.content,
    this.constants = kDefaultConstants,
  });

  final ContentBundle content;
  final SimConstants constants;

  WorldSnapshot project(GameState state) {
    final oracle = WeatherOracle(worldSeed: state.worldSeed, content: content);
    final conditions = oracle.conditionsAt(state.simTime);

    return WorldSnapshot(
      trees: [
        for (final tree in state.trees)
          _projectTree(tree, conditions, state.simTime),
      ],
      conditions: conditions,
      timeOfDay01: state.simTime.hourOfDay / 24.0,
      simTime: state.simTime,
      biome: state.biome,
    );
  }

  TreeVisual _projectTree(Tree tree, WorldConditions conditions, SimTime now) {
    final species = content[tree.species];
    final comfort = Comfort.evaluate(
      tree: tree,
      species: species,
      conditions: conditions,
      constants: constants,
    );

    return TreeVisual(
      id: tree.id,
      speciesId: tree.species,
      seed: tree.seed.raw,
      slot: tree.slot,
      growth01: growthFraction(tree),
      stage: tree.stage,
      state: tree.state,
      foliage: foliageFor(tree, species, conditions, comfort),
      comfort: comfort.overall,
      label: '${species.displayName}, ${tree.stage.label.toLowerCase()}',
      detail: describe(tree, species, comfort),
      ageReference: now,
    );
  }

  /// Progress across the entire stage ladder, which is what the generator's
  /// growth front consumes. Stage plus within-stage progress, normalised.
  static double growthFraction(Tree tree) {
    const stages = GrowthStage.values;
    final within = tree.stage.isFinal ? 1.0 : tree.growth.value / 100.0;
    return ((tree.stage.index + within) / (stages.length - 1))
        .clamp(0.0, 1.0)
        .toDouble();
  }

  /// Appearance from vitals.
  ///
  /// Each term is a band excursion normalised by that band's own tolerance, so
  /// a species with a tight nutrient band shows scorch sooner than one with a
  /// forgiving one — without any per-species art or special case.
  FoliageState foliageFor(
    Tree tree,
    TreeSpecies species,
    WorldConditions conditions,
    Comfort comfort,
  ) {
    if (tree.isSnag) {
      return const FoliageState(bareness: 1, droop: 0.2);
    }

    double below(Band band, double value, {double gain = 1.0}) =>
        (math.max(0.0, band.min - value) / band.tolLow * gain)
            .clamp(0.0, 1.0)
            .toDouble();
    double above(Band band, double value, {double gain = 1.0}) =>
        (math.max(0.0, value - band.max) / band.tolHigh * gain)
            .clamp(0.0, 1.0)
            .toDouble();

    // Thirst wilts; poor health also costs turgor, so a sick tree sags even
    // when it has just been watered.
    final thirst = below(species.water, tree.water.value);
    final frailty = (1.0 - tree.health.fraction).clamp(0.0, 1.0);
    final droop = math.max(thirst, frailty * 0.55).clamp(0.0, 1.0).toDouble();

    // Chlorosis from hunger; scorch from excess, plus any burn already taken.
    final pallor = below(species.nutrition, tree.nutrition.value);
    final burn = tree.afflictionOf(AfflictionKind.nutrientBurn)?.severity ?? 0;
    final scorch = math
        .max(above(species.nutrition, tree.nutrition.value), burn)
        .clamp(0.0, 1.0)
        .toDouble();

    // Saturation shows in the soil first — the clearest read a player gets
    // that a tree is drowning — and rain darkens the ground regardless.
    final saturation = above(species.water, tree.water.value);
    final wetness = math
        .max(saturation, conditions.isRaining ? 0.45 : 0.0)
        .clamp(0.0, 1.0)
        .toDouble();

    // Reserved for genuinely thriving trees, so seeing it means something.
    final sparkle =
        (tree.state == HealthState.thriving && comfort.overall > 0.9)
        ? ((tree.health.value - 88) / 12).clamp(0.0, 1.0).toDouble()
        : 0.0;

    // Leaves are shed only when a tree is genuinely in trouble.
    final bareness = tree.health.value < 40
        ? ((40 - tree.health.value) / 55).clamp(0.0, 0.7).toDouble()
        : 0.0;

    return FoliageState(
      droop: droop,
      pallor: pallor,
      scorch: scorch,
      wetness: wetness,
      sparkle: sparkle,
      bareness: bareness,
      flowering: tree.isFlowering ? 1.0 : 0.0,
    );
  }

  /// The spoken description for the accessibility layer.
  ///
  /// Built here, next to the numbers it describes, so it is unit-testable and
  /// cannot drift from what the tree actually looks like.
  static String describe(Tree tree, TreeSpecies species, Comfort comfort) {
    final buffer = StringBuffer()
      ..write(species.displayName)
      ..write(', ')
      ..write(tree.stage.label.toLowerCase())
      ..write(', ')
      ..write(tree.state.label.toLowerCase())
      ..write('. Water ')
      ..write(tree.water.value.round())
      ..write(' of an ideal ')
      ..write(species.water.min.round())
      ..write(' to ')
      ..write(species.water.max.round())
      ..write('. Nutrition ')
      ..write(tree.nutrition.value.round())
      ..write(' of an ideal ')
      ..write(species.nutrition.min.round())
      ..write(' to ')
      ..write(species.nutrition.max.round())
      ..write('.');

    if (tree.state.needsAttention) {
      // Name the cause, not just the symptom: the limiting factor is the one
      // thing a player can act on.
      buffer
        ..write(' Most limited by ')
        ..write(comfort.limitingFactor)
        ..write('.');
    }
    for (final a in tree.afflictions) {
      buffer
        ..write(' ')
        ..write(a.kind.label)
        ..write('.');
    }
    return buffer.toString();
  }
}
