import 'dart:math' as math;

/// A 2-D point. `grow_flora` is pure Dart so that geometry can be generated,
/// tested and exported without a renderer attached; that rules out
/// `dart:ui.Offset`.
class Vec2 {
  const Vec2(this.x, this.y);
  static const Vec2 zero = Vec2(0, 0);

  final double x;
  final double y;

  /// Screen space: y grows downward, so "up" is negative.
  factory Vec2.fromAngle(double radians, [double length = 1]) =>
      Vec2(math.cos(radians) * length, math.sin(radians) * length);

  Vec2 operator +(Vec2 o) => Vec2(x + o.x, y + o.y);
  Vec2 operator -(Vec2 o) => Vec2(x - o.x, y - o.y);
  Vec2 operator *(double s) => Vec2(x * s, y * s);

  double get length => math.sqrt(x * x + y * y);
  double get angle => math.atan2(y, x);

  Vec2 get normalized {
    final l = length;
    return l == 0 ? Vec2.zero : Vec2(x / l, y / l);
  }

  Vec2 rotated(double radians) {
    final c = math.cos(radians);
    final s = math.sin(radians);
    return Vec2(x * c - y * s, x * s + y * c);
  }

  Vec2 lerpTo(Vec2 o, double t) => Vec2(x + (o.x - x) * t, y + (o.y - y) * t);

  /// The normal used to give a branch its width.
  Vec2 get perpendicular => Vec2(-y, x);

  @override
  String toString() => '(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})';
}

class Bounds {
  const Bounds(this.minX, this.minY, this.maxX, this.maxY);

  final double minX, minY, maxX, maxY;

  double get width => maxX - minX;
  double get height => maxY - minY;

  static Bounds around(Iterable<Vec2> points) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final p in points) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
    if (minX > maxX) return const Bounds(0, 0, 0, 0);
    return Bounds(minX, minY, maxX, maxY);
  }

  Bounds inflated(double d) => Bounds(minX - d, minY - d, maxX + d, maxY + d);

  @override
  String toString() =>
      'Bounds(${width.toStringAsFixed(0)}x'
      '${height.toStringAsFixed(0)})';
}
