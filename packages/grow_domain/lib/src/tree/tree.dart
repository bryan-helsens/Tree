import '../values/ids.dart';
import '../values/sim_time.dart';
import '../values/vital.dart';
import 'affliction.dart';
import 'growth_stage.dart';
import 'health_state.dart';

/// One tree. Immutable; the simulator returns new instances.
class Tree {
  const Tree({
    required this.id,
    required this.species,
    required this.seed,
    required this.slot,
    required this.health,
    required this.water,
    required this.nutrition,
    required this.growth,
    required this.stage,
    required this.state,
    required this.plantedAt,
    required this.lastTendedAt,
    required this.criticalHours,
    required this.criticalSightings,
    required this.careNotificationSent,
    required this.timesWatered,
    required this.timesFed,
    required this.afflictions,
    required this.isFlowering,
    required this.discoveredTraits,
    this.diedAt,
  });

  /// A freshly planted seed with the starting vitals a new player sees.
  factory Tree.seedling({
    required TreeId id,
    required SpeciesId species,
    required Seed seed,
    required int slot,
    required SimTime plantedAt,
    double water = 55,
    double nutrition = 50,
  }) => Tree(
    id: id,
    species: species,
    seed: seed,
    slot: slot,
    health: Vital(90),
    water: Vital(water),
    nutrition: Vital(nutrition),
    growth: Vital.zero,
    stage: GrowthStage.seed,
    state: HealthState.healthy,
    plantedAt: plantedAt,
    lastTendedAt: plantedAt,
    criticalHours: 0,
    criticalSightings: 0,
    careNotificationSent: false,
    timesWatered: 0,
    timesFed: 0,
    afflictions: const [],
    isFlowering: false,
    discoveredTraits: const {},
  );

  final TreeId id;
  final SpeciesId species;
  final Seed seed;
  final int slot;

  final Vital health;
  final Vital water;
  final Vital nutrition;

  /// Progress through the *current* stage, 0..100. Never decreases: damage
  /// costs time, not progress (docs/05-simulation.md §5).
  final Vital growth;
  final GrowthStage stage;
  final HealthState state;

  final SimTime plantedAt;
  final SimTime lastTendedAt;

  /// Accumulated hours spent in the critical state. Recovery forgives this at
  /// double rate.
  final double criticalHours;

  /// How many times the player has actually *seen* this tree critical. Death
  /// requires at least two, so nobody loses a tree they never had a chance to
  /// save (docs/05-simulation.md §6).
  final int criticalSightings;

  /// Whether a care notification was ever delivered for this tree. Also gates
  /// death.
  final bool careNotificationSent;

  final int timesWatered;
  final int timesFed;
  final List<Affliction> afflictions;
  final bool isFlowering;
  final Set<TraitId> discoveredTraits;
  final SimTime? diedAt;

  bool get isAlive => state.isAlive;
  bool get isSnag => state == HealthState.snag;

  Duration ageAt(SimTime now) => now.difference(plantedAt);

  Affliction? afflictionOf(AfflictionKind kind) {
    for (final a in afflictions) {
      if (a.kind == kind) return a;
    }
    return null;
  }

  bool has(AfflictionKind kind) => afflictionOf(kind) != null;

  Tree copyWith({
    Vital? health,
    Vital? water,
    Vital? nutrition,
    Vital? growth,
    GrowthStage? stage,
    HealthState? state,
    SimTime? lastTendedAt,
    double? criticalHours,
    int? criticalSightings,
    bool? careNotificationSent,
    int? timesWatered,
    int? timesFed,
    List<Affliction>? afflictions,
    bool? isFlowering,
    Set<TraitId>? discoveredTraits,
    SimTime? diedAt,
  }) => Tree(
    id: id,
    species: species,
    seed: seed,
    slot: slot,
    health: health ?? this.health,
    water: water ?? this.water,
    nutrition: nutrition ?? this.nutrition,
    growth: growth ?? this.growth,
    stage: stage ?? this.stage,
    state: state ?? this.state,
    plantedAt: plantedAt,
    lastTendedAt: lastTendedAt ?? this.lastTendedAt,
    criticalHours: criticalHours ?? this.criticalHours,
    criticalSightings: criticalSightings ?? this.criticalSightings,
    careNotificationSent: careNotificationSent ?? this.careNotificationSent,
    timesWatered: timesWatered ?? this.timesWatered,
    timesFed: timesFed ?? this.timesFed,
    afflictions: afflictions ?? this.afflictions,
    isFlowering: isFlowering ?? this.isFlowering,
    discoveredTraits: discoveredTraits ?? this.discoveredTraits,
    diedAt: diedAt ?? this.diedAt,
  );

  @override
  String toString() =>
      'Tree(${species.raw} ${stage.name} '
      'H${health.value.toStringAsFixed(0)} '
      'W${water.value.toStringAsFixed(0)} '
      'N${nutrition.value.toStringAsFixed(0)} '
      'G${growth.value.toStringAsFixed(0)} ${state.name})';
}
