import 'vec2.dart';

/// One branch of the growth-independent form of a tree.
///
/// Every measurement here is in *mature* coordinates and never changes. Growth
/// reveals a prefix of this; it does not rebuild it. That is the property the
/// whole "watch it grow" promise rests on.
class MatureBranch {
  const MatureBranch({
    required this.spine,
    required this.cumulative,
    required this.widthBase,
    required this.widthTip,
    required this.depth,
    required this.parentIndex,
    required this.branchId,
    required this.attachDistance,
    required this.distanceFromRoot,
    required this.phase,
    required this.flex,
  });

  /// Base to tip, at full maturity.
  final List<Vec2> spine;

  /// Arc length from the base to each spine point. `cumulative.last` is the
  /// branch's mature length.
  final List<double> cumulative;

  final double widthBase;
  final double widthTip;
  final int depth;
  final int parentIndex;
  final int branchId;

  /// Absolute arc length along the *parent* at which this branch attaches.
  ///
  /// Absolute, not a fraction. A fraction moves as the parent extends, which
  /// makes branches migrate along their parent as the tree grows.
  final double attachDistance;

  /// Arc length from the base of the trunk to this branch's base, following
  /// the path through its ancestors. The growth front is compared against it.
  final double distanceFromRoot;

  final double phase;
  final double flex;

  double get matureLength => cumulative.last;
  Vec2 get base => spine.first;

  /// Point at [distance] arc length along the mature spine.
  Vec2 pointAtDistance(double distance) {
    if (distance <= 0) return spine.first;
    if (distance >= matureLength) return spine.last;
    for (var i = 1; i < cumulative.length; i++) {
      if (cumulative[i] >= distance) {
        final span = cumulative[i] - cumulative[i - 1];
        final t = span <= 0 ? 0.0 : (distance - cumulative[i - 1]) / span;
        return spine[i - 1].lerpTo(spine[i], t);
      }
    }
    return spine.last;
  }
}

/// The complete growth-independent form of one individual.
///
/// Depends only on `(rules, seed)`, so it can be built once and kept: growth
/// changes many times a session, but the form behind it never does.
class MatureTree {
  const MatureTree({
    required this.branches,
    required this.maxPathLength,
    required this.trunkWidth,
  });

  final List<MatureBranch> branches;

  /// The longest root-to-tip path. The growth front is expressed as a
  /// fraction of this, so every tree finishes growing at the same moment.
  final double maxPathLength;

  final double trunkWidth;
}
