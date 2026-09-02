import 'player/inventory.dart';
import 'player/progression.dart';
import 'tree/tree.dart';
import 'values/ids.dart';
import 'values/sim_time.dart';

/// The complete simulated state of a save.
///
/// Immutable. The simulator takes one and returns another; nothing mutates in
/// place, which is what makes the determinism property testable.
class GameState {
  const GameState({
    required this.worldSeed,
    required this.simTime,
    required this.trees,
    required this.inventory,
    required this.progression,
    required this.lastInteractionAt,
    required this.biome,
  });

  factory GameState.newGame({
    required Seed worldSeed,
    required SpeciesId starterSpecies,
    BiomeId biome = const BiomeId('woodland'),
  }) {
    const t0 = SimTime.zero;
    return GameState(
      worldSeed: worldSeed,
      simTime: t0,
      trees: [
        Tree.seedling(
          id: const TreeId('tree-1'),
          species: starterSpecies,
          seed: Seed(worldSeed.raw ^ 0x9E3779B9),
          slot: 0,
          plantedAt: t0,
        ),
      ],
      inventory: const Inventory.starting(),
      progression: const Progression.starting(),
      lastInteractionAt: t0,
      biome: biome,
    );
  }

  /// Fixed at first launch. Drives all deterministic generation.
  final Seed worldSeed;

  /// Always sits on the 60-second grid. Monotonic; never decreases.
  final SimTime simTime;

  final List<Tree> trees;
  final Inventory inventory;
  final Progression progression;

  /// When the player last acted or opened the app.
  ///
  /// Dormancy keys off *this*, not off the size of the catch-up window. That
  /// distinction is what lets `run(a→c)` equal `run(a→b)` then `run(b→c)`
  /// even across the dormancy boundary — a chunked replay and a single jump
  /// see the same absence.
  final SimTime lastInteractionAt;

  final BiomeId biome;

  Iterable<Tree> get livingTrees => trees.where((t) => t.isAlive);

  Tree? treeById(TreeId id) {
    for (final t in trees) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Hours since the player last interacted, at [at].
  double awayHoursAt(SimTime at) =>
      (at.ms - lastInteractionAt.ms) / SimTime.hourMs;

  GameState copyWith({
    SimTime? simTime,
    List<Tree>? trees,
    Inventory? inventory,
    Progression? progression,
    SimTime? lastInteractionAt,
  }) => GameState(
    worldSeed: worldSeed,
    simTime: simTime ?? this.simTime,
    trees: trees ?? this.trees,
    inventory: inventory ?? this.inventory,
    progression: progression ?? this.progression,
    lastInteractionAt: lastInteractionAt ?? this.lastInteractionAt,
    biome: biome,
  );

  /// Marks the player as present. Clears dormancy accrual from this moment on.
  GameState touched(SimTime at) => copyWith(lastInteractionAt: at);

  @override
  String toString() =>
      'GameState(t=${simTime.ms}, ${trees.length} trees, $progression, $inventory)';
}
