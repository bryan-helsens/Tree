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

/// A species' colour identity. Kept as plain ARGB integers so this package
/// stays free of any rendering dependency.
class FoliagePalette {
  const FoliagePalette({
    required this.leafDark,
    required this.leafMid,
    required this.leafLight,
    required this.barkDark,
    required this.barkLight,
    required this.flowerColor,
  });

  final int leafDark;
  final int leafMid;
  final int leafLight;
  final int barkDark;
  final int barkLight;
  final int flowerColor;

  /// Colour for one leaf, given its per-leaf tone jitter and the tree's
  /// current condition.
  int leafColor(double tone, FoliageState s) {
    // Base variation across the canopy, so it is never one flat green.
    var c = tone < 0.5
        ? _lerpArgb(leafDark, leafMid, tone * 2)
        : _lerpArgb(leafMid, leafLight, (tone - 0.5) * 2);

    if (s.pallor > 0) c = _lerpArgb(c, _pallidOf(c), s.pallor * 0.85);
    if (s.scorch > 0) c = _lerpArgb(c, _scorchTone, s.scorch * 0.75);
    if (s.wetness > 0) c = _lerpArgb(c, _darken(c, 0.82), s.wetness * 0.35);
    return c;
  }

  int barkColor(double t, FoliageState s) {
    final c = _lerpArgb(barkDark, barkLight, t);
    return s.wetness > 0 ? _lerpArgb(c, _darken(c, 0.7), s.wetness * 0.5) : c;
  }

  static const int _scorchTone = 0xFF7A4A26;

  /// Nutrient-starved leaves lose chlorophyll: they go yellow, not grey.
  static int _pallidOf(int c) {
    final r = (c >> 16) & 0xFF, g = (c >> 8) & 0xFF, b = c & 0xFF;
    final lum = 0.3 * r + 0.6 * g + 0.1 * b;
    return 0xFF000000 |
        (_c(lum * 1.18 + 30) << 16) |
        (_c(lum * 1.22 + 34) << 8) |
        _c(lum * 0.62);
  }

  static int _darken(int c, double f) =>
      0xFF000000 |
      (_c(((c >> 16) & 0xFF) * f) << 16) |
      (_c(((c >> 8) & 0xFF) * f) << 8) |
      _c((c & 0xFF) * f);

  static int _c(double v) => v.clamp(0, 255).round();

  static int _lerpArgb(int a, int b, double t) {
    final u = t.clamp(0.0, 1.0);
    int ch(int shift) {
      final x = (a >> shift) & 0xFF;
      final y = (b >> shift) & 0xFF;
      return (x + (y - x) * u).round() & 0xFF;
    }

    return (0xFF << 24) | (ch(16) << 16) | (ch(8) << 8) | ch(0);
  }
}

/// The one wind function that drives every moving thing in the world.
///
/// Branches, grass, leaves, drifting particles and the animals' lean all read
/// from this. Sharing a single source is why the scene looks like one place
/// with weather in it rather than several independent loops.
class WindField {
  const WindField({
    this.amplitude = 1.0,
    this.gustiness = 0.6,
    this.baseFrequency = 0.35,
  });

  final double amplitude;
  final double gustiness;
  final double baseFrequency;

  /// Displacement at time [t] seconds and world height [y].
  double at(double t, double y) {
    final base =
        math.sin(t * baseFrequency) +
        0.4 * math.sin(t * baseFrequency * 2.2 + 1.1);
    final gust = gustiness * _noise(t * 0.13, y * 0.004);
    // Higher up moves more: the canopy sways while the base holds.
    final heightFactor = (1.0 - (y / -400.0).clamp(-1.0, 0.0)).clamp(0.3, 1.4);
    return amplitude * (base * 0.6 + gust) * heightFactor;
  }

  /// Sway angle in radians for one branch.
  double swayFor(double t, double y, double phase, double flex) =>
      at(t, y) * flex * 0.045 * math.sin(t * 1.7 + phase);

  static double _noise(double x, double y) {
    final xi = x.floor(), yi = y.floor();
    final xf = x - xi, yf = y - yi;
    final u = xf * xf * (3 - 2 * xf);
    final v = yf * yf * (3 - 2 * yf);
    final a = _h(xi, yi), b = _h(xi + 1, yi);
    final c = _h(xi, yi + 1), d = _h(xi + 1, yi + 1);
    return (a + (b - a) * u) + ((c + (d - c) * u) - (a + (b - a) * u)) * v;
  }

  static double _h(int x, int y) {
    var n = x * 374761393 + y * 668265263;
    n = (n ^ (n >>> 13)) * 1274126177;
    return ((n ^ (n >>> 16)) & 0x7FFFFFFF) / 0x7FFFFFFF * 2 - 1;
  }
}
