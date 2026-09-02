import 'dart:math' as math;

import 'package:grow_content/grow_content.dart';
import 'package:grow_domain/grow_domain.dart';

import 'sim_constants.dart';

/// The four band scores and their weighted composite.
class Comfort {
  const Comfort({
    required this.water,
    required this.nutrition,
    required this.light,
    required this.temperature,
    required this.overall,
  });

  final double water;
  final double nutrition;
  final double light;
  final double temperature;

  /// Weighted geometric mean, so one badly wrong vital dominates rather than
  /// being averaged away by three good ones.
  final double overall;

  /// The vital currently costing the most comfort. Drives which explanation
  /// the UI leads with.
  String get limitingFactor {
    var worst = 'water';
    var value = water;
    if (nutrition < value) {
      worst = 'nutrition';
      value = nutrition;
    }
    if (light < value) {
      worst = 'light';
      value = light;
    }
    if (temperature < value) worst = 'temperature';
    return worst;
  }

  static Comfort evaluate({
    required Tree tree,
    required TreeSpecies species,
    required WorldConditions conditions,
    SimConstants constants = kDefaultConstants,
  }) {
    final cw = species.water.comfort(tree.water.value);
    final cn = species.nutrition.comfort(tree.nutrition.value);
    final cl = species.light.comfort(conditions.lightLevel);
    final ct = species.temperature.comfort(conditions.temperature);

    // Geometric mean with weights. A zero in any term drives the composite to
    // zero, which is the intended behaviour.
    final overall = _weightedGeometricMean(
      [cw, cn, cl, ct],
      [
        constants.comfortWeightWater,
        constants.comfortWeightNutrition,
        constants.comfortWeightLight,
        constants.comfortWeightTemperature,
      ],
    );

    return Comfort(
      water: cw,
      nutrition: cn,
      light: cl,
      temperature: ct,
      overall: overall,
    );
  }
}

double _weightedGeometricMean(List<double> values, List<double> weights) {
  var sumW = 0.0;
  var acc = 0.0;
  for (var i = 0; i < values.length; i++) {
    final v = values[i];
    if (v <= 0) return 0.0;
    acc += weights[i] * math.log(v);
    sumW += weights[i];
  }
  if (sumW <= 0) return 0.0;
  final r = math.exp(acc / sumW);
  return r.isFinite ? r.clamp(0.0, 1.0).toDouble() : 0.0;
}
