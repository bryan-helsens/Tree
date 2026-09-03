import 'dart:math' as math;

import 'package:grow_content/grow_content.dart';
import 'package:grow_domain/grow_domain.dart';

import 'growth.dart';

/// Focus-session yields.
///
/// Pure functions, so the balance harness can sweep them and the UI can show a
/// player exactly what a session will pay *before* they commit forty-five
/// minutes to it. Rewards are deterministic for that reason — the seed roll is
/// the only stochastic part.
///
/// See docs/06-economy-and-progression.md §2.
class FocusEconomy {
  const FocusEconomy({
    this.gpCoefficient = 10.0,
    this.gpExponent = 0.8,
    this.gpPerWater = 45,
    this.gpPerNutrient = 190,
    this.gpPerSeedRoll = 2500,
    this.maxSeedChance = 0.35,
    this.dailySoftCapGp = 900,
    this.overCapMultiplier = 0.2,
    this.deepFocusMinutes = 45,
    this.maxSessionMinutes = 120,
    this.minSessionMinutes = 5,
    this.growthPerGp = 0.02,
  });

  final double gpCoefficient;

  /// Below 1, so the marginal minute is worth less as a session lengthens.
  /// Minute 120 is worth about 60% of minute 10 — enough that faking a
  /// six-hour session buys nothing, without punishing genuinely long focus.
  final double gpExponent;

  final int gpPerWater;
  final int gpPerNutrient;
  final int gpPerSeedRoll;
  final double maxSeedChance;
  final int dailySoftCapGp;
  final double overCapMultiplier;
  final int deepFocusMinutes;
  final int maxSessionMinutes;
  final int minSessionMinutes;
  final double growthPerGp;

  /// Diminishing weight on repeated sessions within a day. The first two are
  /// both full weight, so the natural morning-and-evening rhythm is not
  /// penalised; it falls away after that.
  static const List<double> fatigueByIndex = [
    1.00,
    1.00,
    0.85,
    0.70,
    0.55,
    0.40,
  ];
  static const double fatigueFloor = 0.30;

  static double fatigue(int sessionIndexToday) =>
      sessionIndexToday < fatigueByIndex.length
      ? fatigueByIndex[sessionIndexToday]
      : fatigueFloor;

  /// Integrity from measured screen-on time during the session window.
  ///
  /// Never returns zero and there is no failure branch: a session cannot be
  /// failed (Design Charter C2). The 4% grace means glancing at the clock
  /// costs nothing.
  static double integrityFrom({
    required Duration window,
    required Duration screenOn,
  }) {
    if (window.inSeconds <= 0) return 1.0;
    final used = screenOn.inSeconds / window.inSeconds;
    return (1.0 - 1.3 * math.max(0.0, used - 0.04)).clamp(0.35, 1.0).toDouble();
  }

  double rawGp(int minutes) =>
      gpCoefficient * math.pow(minutes.toDouble(), gpExponent);

  FocusYield yieldFor({
    required int minutes,
    required int sessionIndexToday,
    required int streakDays,
    required int gpAlreadyEarnedToday,
    double integrity = 1.0,
    bool deepFocusBonusAlreadyUsed = false,
  }) {
    final clamped = minutes.clamp(minSessionMinutes, maxSessionMinutes);
    final streakMultiplier = 1.0 + math.min(0.50, 0.05 * streakDays);

    var gp =
        rawGp(clamped) *
        fatigue(sessionIndexToday) *
        streakMultiplier *
        integrity.clamp(0.35, 1.0);

    // The soft cap only bites at implausible daily volumes; it exists so the
    // ceiling is bounded, not to police anybody.
    if (gpAlreadyEarnedToday >= dailySoftCapGp) {
      gp *= overCapMultiplier;
    } else if (gpAlreadyEarnedToday + gp > dailySoftCapGp) {
      final under = dailySoftCapGp - gpAlreadyEarnedToday;
      gp = under + (gp - under) * overCapMultiplier;
    }

    final total = gp.round();
    final deep = clamped >= deepFocusMinutes && !deepFocusBonusAlreadyUsed;

    return FocusYield(
      minutes: clamped,
      growthPoints: total,
      water: total ~/ gpPerWater,
      nutrients: total ~/ gpPerNutrient,
      bonusNutrients: deep ? 1 : 0,
      xp: total,
      seedChance: (total / gpPerSeedRoll).clamp(0.0, maxSeedChance).toDouble(),
      growthInjection: total * growthPerGp,
      deepFocusBonus: deep,
      integrity: integrity,
    );
  }
}

class FocusYield {
  const FocusYield({
    required this.minutes,
    required this.growthPoints,
    required this.water,
    required this.nutrients,
    required this.bonusNutrients,
    required this.xp,
    required this.seedChance,
    required this.growthInjection,
    required this.deepFocusBonus,
    required this.integrity,
  });

  final int minutes;
  final int growthPoints;
  final int water;

  /// Base conversion from growth points.
  final int nutrients;

  /// The Deep Focus bonus, kept separate so the completion screen can
  /// celebrate it as its own line rather than folding it invisibly into the
  /// total. Long sessions win on quality; this is the quality.
  final int bonusNutrients;

  int get totalNutrients => nutrients + bonusNutrients;

  final int xp;
  final double seedChance;

  /// Percentage points of the current growth stage, applied on the completion
  /// screen with a visible animation. This is the moment the product exists
  /// for: you put the phone down and the tree changed.
  final double growthInjection;

  final bool deepFocusBonus;
  final double integrity;

  @override
  String toString() =>
      '${minutes}min → ${growthPoints}gp '
      '(💧$water 🌱$nutrients ⭐$xp seed ${(seedChance * 100).toStringAsFixed(1)}%)';
}

/// Applies a completed session's yield to a save.
///
/// Returns the growth that actually landed alongside the new state. The
/// injection goes through [addGrowth], the same path the simulator's own
/// accrual takes, so a reward that finishes a stage carries over instead of
/// being clipped at 100 — and a reward with nowhere to go is reported as zero
/// rather than quietly promised.
({GameState state, double growthApplied}) applyFocusYield(
  GameState state,
  FocusYield y, {
  required ContentBundle content,
  TreeId? focusTree,
}) {
  final inv = state.inventory;
  final progressed = state.progression.addXp(y.xp);

  var growthApplied = 0.0;
  final trees = <Tree>[];
  for (final t in state.trees) {
    if (!t.isAlive || (focusTree != null && t.id != focusTree)) {
      trees.add(t);
      continue;
    }
    final grown = addGrowth(t, content[t.species], y.growthInjection);
    growthApplied = math.max(growthApplied, grown.applied);
    trees.add(grown.tree);
  }

  final next = state.copyWith(
    trees: trees,
    inventory: inv.copyWith(
      water: math.min(inv.waterCap, inv.water + y.water),
      nutrients: math.min(inv.nutrientCap, inv.nutrients + y.totalNutrients),
      waterCap: Inventory.capacityForLevel(progressed.progression.level),
      nutrientCap: Inventory.nutrientCapacityForLevel(
        progressed.progression.level,
      ),
    ),
    progression: progressed.progression,
    lastInteractionAt: state.simTime,
  );
  return (state: next, growthApplied: growthApplied);
}
