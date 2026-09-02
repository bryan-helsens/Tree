import 'package:grow_content/grow_content.dart';
import 'package:grow_domain/grow_domain.dart';
import 'package:grow_sim/grow_sim.dart';

final ContentBundle content = mvpContent();
const SpeciesId oak = SpeciesId('quercus_robur');
const SpeciesId birch = SpeciesId('betula_pendula');

Simulator sim({SimConstants? k}) =>
    Simulator(content: content, constants: k ?? kDefaultConstants);

/// A simulator with the sky pinned, so a test can measure the effect of player
/// care without the weather confounding it.
Simulator simUnder(WeatherKind kind, {int seed = 999, double? rainRate}) =>
    Simulator(
      content: content,
      weatherOverride: FixedWeatherOracle(
        worldSeed: Seed(seed),
        content: content,
        kind: kind,
        rainRateOverride: rainRate,
      ),
    );

GameState newGame({int seed = 12345, SpeciesId species = oak}) =>
    GameState.newGame(worldSeed: Seed(seed), starterSpecies: species);

/// A state whose tree is already grown up a little, for tests that care about
/// mature-tree dynamics rather than the first twenty minutes.
GameState established({
  int seed = 999,
  SpeciesId species = oak,
  double water = 58,
  double nutrition = 52,
  double health = 92,
  GrowthStage stage = GrowthStage.sapling,
}) {
  final base = newGame(seed: seed, species: species);
  return base.copyWith(
    trees: [
      base.trees.first.copyWith(
        water: Vital(water),
        nutrition: Vital(nutrition),
        health: Vital(health),
        stage: stage,
      ),
    ],
  );
}

Tree only(GameState s) => s.trees.first;

/// Compares two states on every field the simulation can move.
void expectStatesEqual(GameState a, GameState b, {String? reason}) {
  if (a.simTime.ms != b.simTime.ms) {
    throw StateError('simTime ${a.simTime.ms} != ${b.simTime.ms} ($reason)');
  }
  if (a.trees.length != b.trees.length) {
    throw StateError('tree count differs ($reason)');
  }
  for (var i = 0; i < a.trees.length; i++) {
    final x = a.trees[i];
    final y = b.trees[i];
    void cmp(String field, double p, double q) {
      if ((p - q).abs() > 1e-9) {
        throw StateError('tree $i $field: $p != $q ($reason)');
      }
    }

    cmp('health', x.health.value, y.health.value);
    cmp('water', x.water.value, y.water.value);
    cmp('nutrition', x.nutrition.value, y.nutrition.value);
    cmp('growth', x.growth.value, y.growth.value);
    cmp('criticalHours', x.criticalHours, y.criticalHours);
    if (x.stage != y.stage) {
      throw StateError('tree $i stage ${x.stage} != ${y.stage} ($reason)');
    }
    if (x.state != y.state) {
      throw StateError('tree $i state ${x.state} != ${y.state} ($reason)');
    }
    if (x.afflictions.length != y.afflictions.length) {
      throw StateError('tree $i affliction count differs ($reason)');
    }
  }
  if (a.inventory.dew != b.inventory.dew) {
    throw StateError('dew ${a.inventory.dew} != ${b.inventory.dew} ($reason)');
  }
}
