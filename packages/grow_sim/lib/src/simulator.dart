import 'dart:math' as math;

import 'package:grow_content/grow_content.dart';
import 'package:grow_domain/grow_domain.dart';

import 'comfort.dart';
import 'rng.dart';
import 'sim_constants.dart';
import 'sim_event.dart';
import 'weather_oracle.dart';

/// The deterministic simulation.
///
/// One code path serves both the 1 Hz online tick and a three-day offline
/// catch-up: they differ only in their bounds. That is what eliminates the
/// class of bug where the offline result disagrees with the online one.
///
/// Steps advance on a fixed 60-second grid anchored to *absolute* time, which
/// gives the property the whole design leans on:
///
///     run(a → c)  ≡  run(a → b) then run(b → c)
///
/// See docs/05-simulation.md.
class Simulator {
  const Simulator({
    required this.content,
    this.constants = kDefaultConstants,
    this.journalCap = 60,
    this.weatherOverride,
  });

  final ContentBundle content;
  final SimConstants constants;

  /// Pins the weather. Tests and the balance harness use this to isolate the
  /// effect of player care from the effect of the sky; production leaves it
  /// null and the oracle is derived from the world seed.
  final WeatherOracle? weatherOverride;

  /// Detailed events are capped for very long windows; the digest always
  /// carries the headline numbers regardless.
  final int journalCap;

  /// Advances [state] to [to], flooring to the step grid.
  ///
  /// [to] before the current time is a no-op rather than an error: a rewound
  /// wall clock produces zero progress, never negative progress.
  SimulationResult run({required GameState state, required SimTime to}) {
    assert(state.simTime.isOnGrid, 'state.simTime must sit on the step grid');

    final target = to.floorToStep;
    final journal = <SimEvent>[];
    final growthByTree = <TreeId, double>{};
    final waterDeltaByTree = <TreeId, double>{};
    var rainHours = 0.0;
    var stageUps = 0;
    var enteredDormancy = false;

    if (target <= state.simTime) {
      return SimulationResult(
        state: state,
        journal: const [],
        digest: SimulationDigest(
          elapsed: Duration.zero,
          growthByTree: const {},
          waterDeltaByTree: const {},
          rainHours: 0,
          dewGained: 0,
          stageUps: 0,
          enteredDormancy: false,
        ),
      );
    }

    final oracle =
        weatherOverride ??
        WeatherOracle(worldSeed: state.worldSeed, content: content);
    final startWater = {for (final t in state.trees) t.id: t.water.value};
    final startGrowthAbs = {
      for (final t in state.trees) t.id: _absoluteGrowth(t),
    };

    final trees = List<Tree>.from(state.trees);
    final startStep = state.simTime.stepIndex;
    final endStep = target.stepIndex;
    const dtHours = SimTime.stepMs / SimTime.hourMs;

    for (var step = startStep; step < endStep; step++) {
      final now = SimTime(step * SimTime.stepMs);
      final conditions = oracle.conditionsAt(now);
      final awayHours = state.awayHoursAt(now);
      final dormant = awayHours > constants.dormancyAfterHours;
      if (dormant) enteredDormancy = true;
      if (conditions.isRaining) rainHours += dtHours;

      // Event rolls fire once per absolute hour slot, so they are independent
      // of how the window was chunked.
      final isHourBoundary = step % 60 == 0;

      for (var i = 0; i < trees.length; i++) {
        final tree = trees[i];
        if (tree.isSnag) continue;
        trees[i] = _stepTree(
          tree: tree,
          state: state,
          conditions: conditions,
          now: now,
          dtHours: dtHours,
          dormant: dormant,
          rollEvents: isHourBoundary,
          journal: journal,
          onStageUp: () => stageUps++,
        );
      }
    }

    for (final t in trees) {
      growthByTree[t.id] = _absoluteGrowth(t) - (startGrowthAbs[t.id] ?? 0);
      waterDeltaByTree[t.id] = t.water.value - (startWater[t.id] ?? 0);
    }

    // Passive dew: +1 per 3 hours away, capped. Guarantees a returning player
    // always has at least one meaningful action (Design Charter C5).
    final awayAtEnd = state.awayHoursAt(target);
    final dewTarget = awayAtEnd <= 0
        ? state.inventory.dew
        : math.min(
            Inventory.dewCap,
            (awayAtEnd / Inventory.dewIntervalHours).floor(),
          );
    final dewGained = math.max(0, dewTarget - state.inventory.dew);

    journal.sort((a, b) {
      final s = b.significance.compareTo(a.significance);
      return s != 0 ? s : a.at.ms.compareTo(b.at.ms);
    });

    return SimulationResult(
      state: state.copyWith(
        simTime: target,
        trees: trees,
        inventory: state.inventory.copyWith(
          dew: state.inventory.dew + dewGained,
        ),
      ),
      journal: journal.length > journalCap
          ? journal.sublist(0, journalCap)
          : journal,
      digest: SimulationDigest(
        elapsed: target.difference(state.simTime),
        growthByTree: growthByTree,
        waterDeltaByTree: waterDeltaByTree,
        rainHours: rainHours,
        dewGained: dewGained,
        stageUps: stageUps,
        enteredDormancy: enteredDormancy,
      ),
    );
  }

  // ─── one tree, one 60-second step ──────────────────────────────────────

  Tree _stepTree({
    required Tree tree,
    required GameState state,
    required WorldConditions conditions,
    required SimTime now,
    required double dtHours,
    required bool dormant,
    required bool rollEvents,
    required List<SimEvent> journal,
    required void Function() onStageUp,
  }) {
    final species = content[tree.species];
    var water = tree.water.value;
    var nutrition = tree.nutrition.value;

    if (dormant) {
      // Asymptotic drift toward a resting equilibrium. Closed form and keyed
      // on absolute time, so it composes exactly like the active path.
      water +=
          (constants.dormancyWaterRest - water) *
          (dtHours / constants.dormancyWaterTauHours);
      nutrition +=
          (constants.dormancyNutritionRest - nutrition) *
          (dtHours / constants.dormancyNutritionTauHours);
    } else {
      water += _waterDelta(tree, species, conditions, dtHours);
      nutrition += _nutritionDelta(tree, species, water, dtHours);
    }

    var next = tree.copyWith(water: Vital(water), nutrition: Vital(nutrition));
    final comfort = Comfort.evaluate(
      tree: next,
      species: species,
      conditions: conditions,
      constants: constants,
    );

    next = _applyHealth(next, species, comfort, dtHours, dormant);
    next = _applyAfflictions(next, dtHours);
    if (!dormant) {
      next = _applyGrowth(
        next,
        species,
        comfort,
        dtHours,
        now,
        journal,
        onStageUp,
      );
    }
    next = _applyState(next, comfort, dtHours, now, journal, dormant);

    if (rollEvents && !dormant) {
      next = _rollHourlyEvents(next, species, comfort, state, now, journal);
    }
    return next;
  }

  double _waterDelta(
    Tree tree,
    TreeSpecies species,
    WorldConditions c,
    double dtHours,
  ) {
    // Saturated soil sheds water rather than absorbing all of it, which caps
    // how far the weather alone can push a tree past its band.
    final saturation = ((tree.water.value - 85.0) / 15.0)
        .clamp(0.0, 1.0)
        .toDouble();
    final rain = c.rainRate * (1.0 - saturation);
    // Drying is proportional to wetness, so moisture decays asymptotically
    // toward a floor instead of hitting zero and sitting at maximum damage.
    final wetnessFactor = 0.5 + 0.5 * (tree.water.value / 100.0);
    final nightFactor = c.isNight ? 0.7 : 1.0;
    final loss =
        constants.baseWaterLossPerHour *
        species.waterUse *
        tree.stage.drink *
        c.weather.evaporation *
        nightFactor *
        wetnessFactor;
    return (rain - loss) * dtHours;
  }

  double _nutritionDelta(
    Tree tree,
    TreeSpecies species,
    double water,
    double dtHours,
  ) {
    // Uptake scales with the tree's capacity to grow, so a stalled tree barely
    // consumes and neglect does not compound into a second failing vital.
    final gate = _healthGate(tree.health.value);
    final uptake =
        constants.baseNutrientLossPerHour *
        species.nutrientUse *
        tree.stage.drink *
        gate;
    final leach = water > constants.leachThreshold
        ? constants.leachRate * (water - constants.leachThreshold)
        : 0.0;
    return -(uptake + leach) * dtHours;
  }

  double _healthGate(double health) =>
      ((health - constants.healthGateFloor) / constants.healthGateSpan)
          .clamp(0.0, 1.0)
          .toDouble();

  Tree _applyHealth(
    Tree tree,
    TreeSpecies species,
    Comfort comfort,
    double dtHours,
    bool dormant,
  ) {
    final target = 100.0 * comfort.overall;
    final h = tree.health.value;
    double delta;
    if (h < target) {
      delta = constants.healPerHour * species.vigor * (target - h) / 100.0;
    } else {
      final harm =
          constants.harmPerHour *
          (1.0 - species.resilience) *
          (h - target) /
          100.0;
      delta = -(dormant ? harm * constants.dormancyHarmScale : harm);
    }

    // Afflictions apply on top of band discomfort.
    var afflictionDrag = 0.0;
    for (final a in tree.afflictions) {
      afflictionDrag += constants.afflictionHealthPenalty * a.severity / 100.0;
    }
    delta -= afflictionDrag * (dormant ? constants.dormancyHarmScale : 1.0);

    var newHealth = h + delta * dtHours;

    // The floor that makes "a tree cannot die from absence alone" true by
    // construction rather than by special case.
    if (dormant && newHealth < constants.dormancyHealthFloor) {
      newHealth = math.max(newHealth, constants.dormancyHealthFloor);
      if (h < constants.dormancyHealthFloor) newHealth = h;
    }
    return tree.copyWith(health: Vital(newHealth));
  }

  Tree _applyAfflictions(Tree tree, double dtHours) {
    if (tree.afflictions.isEmpty) return tree;
    final kept = <Affliction>[];
    for (final a in tree.afflictions) {
      final decayed = a.severity - constants.afflictionDecayPerHour * dtHours;
      if (decayed > 0.01) kept.add(a.copyWith(severity: decayed));
    }
    return kept.length == tree.afflictions.length &&
            kept.isNotEmpty &&
            kept.first.severity == tree.afflictions.first.severity
        ? tree
        : tree.copyWith(afflictions: kept);
  }

  Tree _applyGrowth(
    Tree tree,
    TreeSpecies species,
    Comfort comfort,
    double dtHours,
    SimTime now,
    List<SimEvent> journal,
    void Function() onStageUp,
  ) {
    if (tree.stage.isFinal) return tree;
    final hours = species.hoursForStage(tree.stage);
    if (hours <= 0) return tree;

    final rate =
        (100.0 / hours) *
        math.pow(comfort.overall, constants.growthComfortExponent) *
        _healthGate(tree.health.value);
    // Growth never reverses: damage costs time, not progress.
    final g = tree.growth.value + rate * dtHours;

    if (g >= 100.0) {
      final nextStage = tree.stage.next;
      onStageUp();
      journal.add(
        SimEvent(
          kind: SimEventKind.growthStageUp,
          at: now,
          treeId: tree.id,
          message:
              '${species.displayName} became a ${nextStage.label.toLowerCase()}',
        ),
      );
      return tree.copyWith(stage: nextStage, growth: Vital.zero);
    }
    return tree.copyWith(growth: Vital(g));
  }

  Tree _applyState(
    Tree tree,
    Comfort comfort,
    double dtHours,
    SimTime now,
    List<SimEvent> journal,
    bool dormant,
  ) {
    final resolved = dormant
        ? HealthState.dormant
        : HealthThresholds.resolve(
            health: tree.health.value,
            comfort: comfort.overall,
            previous: tree.state == HealthState.dormant
                ? HealthState.stressed
                : tree.state,
          );

    var criticalHours = tree.criticalHours;
    if (resolved == HealthState.critical) {
      criticalHours += dtHours;
    } else {
      // Recovery forgives at double rate: one good session erases two days.
      criticalHours = math.max(
        0,
        criticalHours - constants.criticalRecoveryRate * dtHours,
      );
    }

    var next = tree.copyWith(state: resolved, criticalHours: criticalHours);

    if (resolved != tree.state) {
      if (resolved == HealthState.dormant) {
        journal.add(
          SimEvent(
            kind: SimEventKind.enteredDormancy,
            at: now,
            treeId: tree.id,
            message: 'Your forest settled into rest while you were away',
          ),
        );
      } else if (resolved.needsAttention && !tree.state.needsAttention) {
        journal.add(
          SimEvent(
            kind: SimEventKind.healthStateChanged,
            at: now,
            treeId: tree.id,
            message: 'A tree became ${resolved.label.toLowerCase()}',
          ),
        );
      }
    }

    // Death is deliberately hard to reach, and never reachable from absence.
    final eligible =
        criticalHours >= constants.criticalHoursToDeath &&
        next.criticalSightings >= constants.minCriticalSightings &&
        next.careNotificationSent &&
        !dormant;
    if (eligible) {
      journal.add(
        SimEvent(
          kind: SimEventKind.becameSnag,
          at: now,
          treeId: tree.id,
          message:
              'A tree became standing deadwood. It will still shelter life.',
        ),
      );
      next = next.copyWith(state: HealthState.snag, diedAt: now);
    }
    return next;
  }

  Tree _rollHourlyEvents(
    Tree tree,
    TreeSpecies species,
    Comfort comfort,
    GameState state,
    SimTime now,
    List<SimEvent> journal,
  ) {
    final rng = Xorshift128.forSlot([
      state.worldSeed.raw,
      hashString(tree.id.raw),
      now.hourIndex,
    ]);
    var next = tree;

    // Nutrient burn is not a random roll: past the margin it simply happens,
    // so the cause is always legible to the player.
    final burnEdge = species.nutrition.max + constants.nutrientBurnMargin;
    if (tree.nutrition.value > burnEdge &&
        !tree.has(AfflictionKind.nutrientBurn)) {
      next = _addAffliction(
        next,
        AfflictionKind.nutrientBurn,
        0.4,
        now,
        journal,
      );
    }

    if (tree.water.value > constants.fungusWetThreshold &&
        !tree.has(AfflictionKind.fungus) &&
        rng.chance(constants.fungusChancePerHour)) {
      next = _addAffliction(next, AfflictionKind.fungus, 0.35, now, journal);
    }

    final overwaterFactor =
        1.0 + 3.0 * math.max(0.0, (tree.water.value - 80.0) / 20.0);
    final pestChance =
        constants.pestBaseChancePerHour *
        overwaterFactor *
        (1.0 - species.pestResistance) *
        (1.0 - 0.6 * comfort.overall);
    if (!tree.has(AfflictionKind.pest) && rng.chance(pestChance)) {
      next = _addAffliction(next, AfflictionKind.pest, 0.3, now, journal);
    }

    // Wildlife responds to how well the forest is doing, so an animal showing
    // up is information rather than ambience.
    final attract =
        comfort.overall *
        tree.stage.attract *
        (species.animalAttraction + (tree.isFlowering ? 0.6 : 0.0));
    if (rng.chance(constants.animalVisitBaseChance * attract)) {
      journal.add(
        SimEvent(
          kind: SimEventKind.animalVisit,
          at: now,
          treeId: tree.id,
          message: 'Something visited the ${species.displayName}',
        ),
      );
    }
    return next;
  }

  Tree _addAffliction(
    Tree tree,
    AfflictionKind kind,
    double severity,
    SimTime now,
    List<SimEvent> journal,
  ) {
    journal.add(
      SimEvent(
        kind: SimEventKind.afflictionStarted,
        at: now,
        treeId: tree.id,
        message: kind.explanation,
      ),
    );
    return tree.copyWith(
      afflictions: [
        ...tree.afflictions,
        Affliction(kind: kind, severity: severity, startedAtMs: now.ms),
      ],
    );
  }

  /// Total growth across all completed stages plus progress in the current
  /// one, so the digest can report a monotonic figure.
  static double _absoluteGrowth(Tree t) =>
      t.stage.index * 100.0 + t.growth.value;
}
