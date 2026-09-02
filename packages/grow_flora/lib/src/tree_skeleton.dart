import 'vec2.dart';

/// One woody segment: a curved spine with a width that tapers along it.
///
/// Branches are polylines, not straight lines. A tree built from straight
/// segments reads as a diagram; the curvature is most of what makes it read as
/// a plant.
class Branch {
  const Branch({
    required this.spine,
    required this.widthBase,
    required this.widthTip,
    required this.depth,
    required this.extension,
    required this.phase,
    required this.flex,
    required this.parentIndex,
    required this.branchId,
  });

  /// Base to tip. At least two points.
  final List<Vec2> spine;

  final double widthBase;
  final double widthTip;
  final int depth;

  /// Fraction of this branch's mature length that has grown, 0..1. A branch
  /// at 0.4 is not a shorter branch — it is a prefix of the same branch.
  final double extension;

  /// Per-branch wind phase, so the canopy does not move as one rigid block.
  final double phase;

  /// Wind response. Thin twigs move most; the trunk barely moves at all.
  final double flex;

  final int parentIndex;

  /// Stable identity within the tree. Independent of growth and of traversal
  /// order, so this branch is the same branch at every stage of growth.
  final int branchId;

  Vec2 get base => spine.first;
  Vec2 get tip => spine.last;

  double get length {
    var total = 0.0;
    for (var i = 1; i < spine.length; i++) {
      total += (spine[i] - spine[i - 1]).length;
    }
    return total;
  }

  double widthAt(double t) => widthBase + (widthTip - widthBase) * t;

  /// Point at parameter `t` along the spine, 0..1.
  Vec2 pointAt(double t) {
    if (t <= 0) return spine.first;
    if (t >= 1) return spine.last;
    final scaled = t * (spine.length - 1);
    final i = scaled.floor();
    return spine[i].lerpTo(spine[i + 1], scaled - i);
  }

  Vec2 directionAt(double t) {
    final scaled = (t * (spine.length - 1)).clamp(0, spine.length - 2.0);
    final i = scaled.floor();
    return (spine[i + 1] - spine[i]).normalized;
  }
}

/// A single leaf instance. Rendered as an instanced textured quad in the game;
/// drawn directly in previews.
class Leaf {
  const Leaf({
    required this.position,
    required this.angle,
    required this.scale,
    required this.tone,
    required this.phase,
    required this.depth,
  });

  final Vec2 position;
  final double angle;
  final double scale;

  /// Per-leaf colour jitter in 0..1, so a canopy is not one flat green.
  final double tone;

  final double phase;

  /// Distance from the trunk, normalised. Drives self-shading.
  final double depth;
}

/// A cluster of leaves anchored to a branch tip.
class LeafCluster {
  const LeafCluster({
    required this.anchor,
    required this.radius,
    required this.leaves,
    required this.openness,
    required this.branchIndex,
  });

  final Vec2 anchor;
  final double radius;
  final List<Leaf> leaves;

  /// How far this cluster has opened, 0..1. Drives sprite scale and alpha.
  final double openness;

  final int branchIndex;
}

/// The complete generated form of one individual tree.
class TreeSkeleton {
  const TreeSkeleton({
    required this.branches,
    required this.clusters,
    required this.bounds,
    required this.growth01,
    required this.trunkBase,
  });

  final List<Branch> branches;
  final List<LeafCluster> clusters;
  final Bounds bounds;
  final double growth01;
  final Vec2 trunkBase;

  int get leafCount => clusters.fold(0, (sum, c) => sum + c.leaves.length);

  int get segmentCount =>
      branches.fold(0, (sum, b) => sum + b.spine.length - 1);

  double get height => bounds.height;
}
