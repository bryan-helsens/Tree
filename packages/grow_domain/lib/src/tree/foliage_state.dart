import 'dart:math' as math;

/// How a tree looks right now, derived entirely from simulation state.
///
/// Health is a set of continuous uniforms rather than a set of drawings. This
/// is what makes 7 stages x 5 health states x 4 seasons x N species tractable:
/// none of it is art, all of it is numbers lerped toward a target.
class FoliageState {
  const FoliageState({
    this.droop = 0,
    this.pallor = 0,
    this.scorch = 0,
    this.wetness = 0,
    this.sparkle = 0,
    this.bareness = 0,
    this.flowering = 0,
  });

  /// Leaves and thin branches sag. Driven by moisture below the band.
  final double droop;

  /// Colour desaturates toward yellow-green. Driven by nutrition below band.
  final double pallor;

  /// Leaf edges darken and brown. Driven by nutrition above band.
  final double scorch;

  /// Soil darkens, sheen appears, movement slows. Moisture above band.
  final double wetness;

  /// Occasional bright motes. Only when genuinely thriving, so it stays a
  /// reward rather than decoration.
  final double sparkle;

  /// Leaf loss, from severe ill health or winter.
  final double bareness;

  final double flowering;

  bool get isHealthy => droop < 0.15 && pallor < 0.15 && scorch < 0.15;

  static FoliageState lerp(FoliageState a, FoliageState b, double t) =>
      FoliageState(
        droop: a.droop + (b.droop - a.droop) * t,
        pallor: a.pallor + (b.pallor - a.pallor) * t,
        scorch: a.scorch + (b.scorch - a.scorch) * t,
        wetness: a.wetness + (b.wetness - a.wetness) * t,
        sparkle: a.sparkle + (b.sparkle - a.sparkle) * t,
        bareness: a.bareness + (b.bareness - a.bareness) * t,
        flowering: a.flowering + (b.flowering - a.flowering) * t,
      );

  @override
  String toString() =>
      'Foliage(droop ${droop.toStringAsFixed(2)}, '
      'pallor ${pallor.toStringAsFixed(2)}, '
      'scorch ${scorch.toStringAsFixed(2)}, '
      'wet ${wetness.toStringAsFixed(2)})';
}

/// Interpolates toward a target, framerate-independently.
///
/// Condition changes are visible over a couple of seconds rather than
/// snapping: watering a tree should look like relief, not like a value
/// changing. `halfLife` is the time to close half the remaining distance.
FoliageState approachFoliage(
  FoliageState current,
  FoliageState target,
  double dtSeconds, {
  double halfLife = 0.9,
}) {
  if (dtSeconds <= 0) return current;
  final t = 1 - math.pow(0.5, dtSeconds / halfLife).toDouble();
  return FoliageState.lerp(current, target, t.clamp(0.0, 1.0));
}
