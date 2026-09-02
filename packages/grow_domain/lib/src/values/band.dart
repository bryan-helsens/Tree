import 'dart:math' as math;

/// A comfort band with asymmetric tolerances.
///
/// One function serves every vital. The exponent makes the penalty gentle just
/// outside the band and steep further out, which is what teaches "close enough
/// is fine, but more is not better" without a tutorial.
///
/// See docs/05-simulation.md §2.
class Band {
  const Band({
    required this.min,
    required this.max,
    required this.tolLow,
    required this.tolHigh,
  }) : assert(min <= max, 'band min must not exceed max'),
       assert(tolLow > 0 && tolHigh > 0, 'tolerances must be positive');

  /// Ideal range, inclusive.
  final double min;
  final double max;

  /// Distance below [min] at which comfort reaches zero.
  final double tolLow;

  /// Distance above [max] at which comfort reaches zero. Deliberately tighter
  /// than [tolLow] for water and nutrition: roots suffocate faster than leaves
  /// wilt, and nutrient burn is harsher than nutrient hunger.
  final double tolHigh;

  static const double _exponent = 1.35;

  /// Comfort in `[0, 1]`.
  double comfort(double x) {
    if (x >= min && x <= max) return 1.0;
    final d = x < min ? (min - x) / tolLow : (x - max) / tolHigh;
    final c = 1.0 - math.pow(d, _exponent);
    return c.clamp(0.0, 1.0).toDouble();
  }

  /// True when [x] sits inside the ideal range.
  bool contains(double x) => x >= min && x <= max;

  /// Signed distance outside the band; 0 when inside. Negative below, positive
  /// above. Used by the UI to warn before an action overshoots.
  double excursion(double x) {
    if (x < min) return x - min;
    if (x > max) return x - max;
    return 0;
  }

  double get midpoint => (min + max) / 2;

  Map<String, Object?> toJson() => {
    'min': min,
    'max': max,
    'tolLow': tolLow,
    'tolHigh': tolHigh,
  };

  factory Band.fromJson(Map<String, Object?> j) => Band(
    min: (j['min']! as num).toDouble(),
    max: (j['max']! as num).toDouble(),
    tolLow: (j['tolLow']! as num).toDouble(),
    tolHigh: (j['tolHigh']! as num).toDouble(),
  );

  @override
  String toString() => 'Band($min–$max, −$tolLow/+$tolHigh)';
}
