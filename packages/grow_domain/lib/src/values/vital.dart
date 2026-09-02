/// A tree vital in `[0, 100]`, clamped on construction.
///
/// Clamping at the type boundary removes the entire class of "health reached
/// 103 and the bar overflowed" bug, and guarantees the simulation cannot
/// produce a NaN that propagates silently.
extension type const Vital._(double value) {
  factory Vital(double v) {
    if (v.isNaN) return const Vital._(0);
    return Vital._(v < 0 ? 0 : (v > 100 ? 100 : v));
  }

  static const Vital zero = Vital._(0);
  static const Vital full = Vital._(100);

  Vital operator +(double d) => Vital(value + d);
  Vital operator -(double d) => Vital(value - d);

  bool operator <(double o) => value < o;
  bool operator <=(double o) => value <= o;
  bool operator >(double o) => value > o;
  bool operator >=(double o) => value >= o;

  /// `value` as a 0..1 fraction.
  double get fraction => value / 100.0;
}
