import 'dart:math' as math;

import 'branch_rules.dart';
import 'mature_tree.dart';
import 'tree_skeleton.dart';
import 'vec2.dart';

/// Generates a tree's form from `(rules, seed)`, then reveals it with growth.
///
/// The two halves are deliberately separate:
///
///  * [buildMature] produces the individual's permanent form. It depends only
///    on the rules and the seed, so it can be built once and kept.
///  * [grow] reveals a *prefix* of that form. It never rebuilds anything, so
///    a branch cannot change shape, move, or shorten as the tree ages.
///
/// Growth advances a single front outward from the root, measured in arc
/// length. A branch appears when the front reaches its attachment point and
/// extends from there. That one rule replaces per-branch emergence thresholds
/// and makes monotonic growth true by construction rather than by tuning.
class TreeGenerator {
  const TreeGenerator();

  /// Shapes how the front advances. Below 1 so early growth is visible
  /// quickly and late growth feels earned.
  static const double _frontExponent = 0.80;

  /// Thickening lags extension, which is how real trunks behave and why an
  /// old tree reads as old rather than merely large.
  static const double _widthExponent = 0.78;

  TreeSkeleton generate({
    required BranchRules rules,
    required int seed,
    required double growth01,
  }) => grow(buildMature(rules: rules, seed: seed), growth01, rules);

  // ─── the permanent form ────────────────────────────────────────────────

  MatureTree buildMature({required BranchRules rules, required int seed}) {
    final branches = <MatureBranch>[];

    final trunk = _buildBranch(
      rules: rules,
      rng: _Rng(_branchSeed(seed, 1)),
      start: Vec2.zero,
      direction: const Vec2(0, -1),
      length: rules.trunkLength,
      widthBase: rules.trunkWidth,
      widthTip: rules.trunkWidth * rules.taper,
      depth: 0,
      sinuosity: rules.trunkSinuosity,
      parentIndex: -1,
      branchId: 1,
      attachDistance: 0,
      distanceFromRoot: 0,
    );
    branches.add(trunk);

    _expand(
      rules: rules,
      seed: seed,
      parentId: 1,
      parent: trunk,
      parentIndex: 0,
      depth: 1,
      branches: branches,
    );

    var maxPath = 0.0;
    for (final b in branches) {
      final reach = b.distanceFromRoot + b.matureLength;
      if (reach > maxPath) maxPath = reach;
    }

    return MatureTree(
      branches: branches,
      maxPathLength: maxPath <= 0 ? 1 : maxPath,
      trunkWidth: rules.trunkWidth,
    );
  }

  void _expand({
    required BranchRules rules,
    required int seed,
    required int parentId,
    required MatureBranch parent,
    required int parentIndex,
    required int depth,
    required List<MatureBranch> branches,
  }) {
    if (depth > rules.maxDepth) return;

    // Each branch draws from its own generator, keyed to a stable identity in
    // the tree rather than to a position in one long shared sequence. A shared
    // sequence makes any change upstream reshape everything downstream.
    final rng = _Rng(_branchSeed(seed, parentId));
    final childCount = rules.childrenPerBranch;
    var side = rng.chance(0.5) ? 1.0 : -1.0;

    for (var i = 0; i < childCount; i++) {
      // Children attach along the upper part of the parent; the span below
      // firstNodeAt stays clean.
      final span = 1.0 - rules.firstNodeAt;
      final fraction =
          (rules.firstNodeAt +
                  span * ((i + 0.5) / childCount) +
                  rng.range(-0.05, 0.05))
              .clamp(0.05, 0.98)
              .toDouble();
      final attach = fraction * parent.matureLength;

      final origin = parent.pointAtDistance(attach);
      final parentDir = _directionAtDistance(parent, attach);

      // Angles narrow with depth, so successive generations turn back toward
      // vertical and the canopy closes into a dome instead of spreading flat.
      final decay = rules.angleRangeAt(depth - 1);
      final angle =
          (rng.range(rules.branchAngleMinRad, rules.branchAngleMaxRad) +
              rng.range(-rules.angleJitterRad, rules.angleJitterRad)) *
          decay;
      final sided =
          angle * side * (1.0 + rng.range(-rules.asymmetry, rules.asymmetry));

      final childId = _childId(parentId, i);
      final wBase = _widthAtFraction(parent, fraction) * rules.taper;
      final child = _buildBranch(
        rules: rules,
        rng: _Rng(_branchSeed(seed, childId)),
        start: origin,
        direction: parentDir.rotated(sided),
        length: parent.matureLength * rules.lengthDecay * rng.range(0.82, 1.18),
        widthBase: wBase,
        widthTip: wBase * rules.taper,
        depth: depth,
        sinuosity: rules.trunkSinuosity * 0.6,
        parentIndex: parentIndex,
        branchId: childId,
        attachDistance: attach,
        distanceFromRoot: parent.distanceFromRoot + attach,
      );
      final childIndex = branches.length;
      branches.add(child);

      _expand(
        rules: rules,
        seed: seed,
        parentId: childId,
        parent: child,
        parentIndex: childIndex,
        depth: depth + 1,
        branches: branches,
      );
      side = -side;
    }

    // Apical extension: the parent continues past its last child. Without it
    // a tree is a bush of even forks; with it, it has a leader.
    if (rules.apicalExtension > 0.01) {
      final leaderId = _childId(parentId, 15);
      final wBase = parent.widthTip;
      final leader = _buildBranch(
        rules: rules,
        rng: _Rng(_branchSeed(seed, leaderId)),
        start: parent.spine.last,
        direction: _directionAtDistance(parent, parent.matureLength),
        length:
            parent.matureLength * rules.apicalExtension * rng.range(0.85, 1.15),
        widthBase: wBase,
        widthTip: wBase * rules.taper,
        depth: depth,
        sinuosity: rules.trunkSinuosity * 0.5,
        parentIndex: parentIndex,
        branchId: leaderId,
        attachDistance: parent.matureLength,
        distanceFromRoot: parent.distanceFromRoot + parent.matureLength,
      );
      final leaderIndex = branches.length;
      branches.add(leader);

      _expand(
        rules: rules,
        seed: seed,
        parentId: leaderId,
        parent: leader,
        parentIndex: leaderIndex,
        depth: depth + 1,
        branches: branches,
      );
    }
  }

  /// Walks a branch forward, bending it as it goes.
  ///
  /// Three forces act at every step: light pulls the tip upward, gravity sags
  /// it, and noise keeps it from being a clean arc. Thin branches feel all
  /// three more strongly than thick ones, which is why twigs curl and trunks
  /// stand.
  MatureBranch _buildBranch({
    required BranchRules rules,
    required _Rng rng,
    required Vec2 start,
    required Vec2 direction,
    required double length,
    required double widthBase,
    required double widthTip,
    required int depth,
    required double sinuosity,
    required int parentIndex,
    required int branchId,
    required double attachDistance,
    required double distanceFromRoot,
  }) {
    // Fixed per depth, deliberately not derived from length: a length-varying
    // step count would change how many random draws this branch makes.
    final steps = (12 - depth).clamp(4, 12);
    final stepLength = length / steps;
    final spine = <Vec2>[start];
    final cumulative = <double>[0];

    var pos = start;
    var dir = direction.normalized;
    final thinness =
        1.0 - (widthBase / (rules.trunkWidth + 0.001)).clamp(0.0, 1.0);

    for (var i = 0; i < steps; i++) {
      final t = (i + 1) / steps;
      const up = Vec2(0, -1);
      final photo =
          _signedAngleBetween(dir, up) *
          rules.phototropism *
          0.16 *
          (0.35 + 0.65 * thinness);
      final droop =
          rules.gravityDroop * 0.18 * t * thinness * (dir.x >= 0 ? 1.0 : -1.0);
      final noise =
          rng.range(-1.0, 1.0) * rules.wobble * 0.14 +
          rng.range(-1.0, 1.0) * sinuosity * 0.10;

      dir = dir.rotated(photo + droop + noise).normalized;
      pos = pos + dir * stepLength;
      spine.add(pos);
      cumulative.add(cumulative.last + stepLength);
    }

    return MatureBranch(
      spine: spine,
      cumulative: cumulative,
      widthBase: widthBase,
      widthTip: widthTip,
      depth: depth,
      parentIndex: parentIndex,
      branchId: branchId,
      attachDistance: attachDistance,
      distanceFromRoot: distanceFromRoot,
      phase: rng.range(0, math.pi * 2),
      // Thin branches move most. One expression drives every twig in the
      // world's response to the shared wind field.
      flex: (1.0 / (widthBase + 0.6)).clamp(0.0, 3.0).toDouble(),
    );
  }

  // ─── revealing it ──────────────────────────────────────────────────────

  TreeSkeleton grow(MatureTree mature, double growth01, BranchRules rules) {
    final g = growth01.clamp(0.0, 1.0).toDouble();
    final front = mature.maxPathLength * math.pow(g, _frontExponent).toDouble();
    final widthScale = math.pow(g, _widthExponent).toDouble();

    final visible = <Branch>[];
    final sourceIndex = <int>[];
    final hasVisibleChild = List<bool>.filled(mature.branches.length, false);
    final childExtension = List<double>.filled(mature.branches.length, 0);

    for (var i = 0; i < mature.branches.length; i++) {
      final m = mature.branches[i];
      // The front has to reach a branch's attachment point before it exists.
      // No emergence threshold, no per-branch bookkeeping: one rule.
      final grown = front - m.distanceFromRoot;
      if (grown <= 0) continue;

      final length = math.min(grown, m.matureLength);
      final extension = (length / m.matureLength).clamp(0.0, 1.0).toDouble();

      if (m.parentIndex >= 0) {
        hasVisibleChild[m.parentIndex] = true;
        if (extension > childExtension[m.parentIndex]) {
          childExtension[m.parentIndex] = extension;
        }
      }

      visible.add(_prefix(m, length, extension, widthScale));
      sourceIndex.add(i);
    }

    var maxDepth = 0;
    for (final b in visible) {
      if (b.depth > maxDepth) maxDepth = b.depth;
    }

    // Foliage sits on the terminal shoots and on the outer structure that
    // carries them. Terminal-only leaves ball up at the tips and read as
    // pom-poms on bare sticks.
    final clusters = <LeafCluster>[];
    for (var vi = 0; vi < visible.length; vi++) {
      final src = sourceIndex[vi];
      final b = visible[vi];
      final terminal = !hasVisibleChild[src];
      final carrier = b.depth >= maxDepth - 1;
      if (!terminal && !carrier) continue;

      // A branch whose children are still unfurling keeps its own leaves,
      // handing them over as the children take up the space.
      final handover = 1.0 - childExtension[src];
      final density = terminal
          ? 1.0
          : (0.55 + 0.45 * handover).clamp(0.0, 1.0).toDouble();
      final openness = _easeOut(b.extension);
      if (openness <= 0.02) continue;

      clusters.add(
        _leafCluster(
          rules: rules,
          rng: _Rng(_branchSeed(b.branchId, 0x5BF03635)),
          branch: b,
          branchIndex: vi,
          growth01: g,
          openness: openness,
          density: density,
        ),
      );
    }

    final points = [
      for (final b in visible) ...b.spine,
      for (final c in clusters)
        for (final l in c.leaves) l.position,
    ];

    return TreeSkeleton(
      branches: visible,
      clusters: clusters,
      bounds: Bounds.around(points.isEmpty ? [Vec2.zero] : points),
      growth01: g,
      trunkBase: Vec2.zero,
    );
  }

  /// The first [length] of a mature branch. A prefix, never a rescale — the
  /// points that exist are exactly the mature points.
  Branch _prefix(
    MatureBranch m,
    double length,
    double extension,
    double widthScale,
  ) {
    final spine = <Vec2>[m.spine.first];
    for (var i = 1; i < m.spine.length; i++) {
      if (m.cumulative[i] >= length) {
        final span = m.cumulative[i] - m.cumulative[i - 1];
        final t = span <= 0 ? 0.0 : (length - m.cumulative[i - 1]) / span;
        spine.add(m.spine[i - 1].lerpTo(m.spine[i], t));
        break;
      }
      spine.add(m.spine[i]);
    }
    if (spine.length < 2) spine.add(m.spine.first + const Vec2(0, -0.4));

    final wBase = m.widthBase * widthScale;
    final wFull = m.widthTip * widthScale;
    return Branch(
      spine: spine,
      widthBase: wBase,
      // A branch still extending tapers to a point: it is a growing shoot,
      // not a blunt cut.
      widthTip:
          (wBase + (wFull - wBase) * extension) * (0.25 + 0.75 * extension),
      depth: m.depth,
      extension: extension,
      phase: m.phase,
      flex: m.flex,
      parentIndex: m.parentIndex,
      branchId: m.branchId,
    );
  }

  LeafCluster _leafCluster({
    required BranchRules rules,
    required _Rng rng,
    required Branch branch,
    required int branchIndex,
    required double growth01,
    required double openness,
    required double density,
  }) {
    // Generous overlap: neighbouring clusters have to merge, or the canopy
    // reads as separate balls of foliage.
    final radius = rules.leafSize * 3.6 * rng.range(0.85, 1.3) * openness;
    final count = math.max(
      2,
      (rules.leafDensity *
              density *
              rng.range(0.7, 1.3) *
              (0.45 + 0.55 * growth01))
          .round(),
    );

    final leaves = <Leaf>[];
    for (var i = 0; i < count; i++) {
      // Bias placement toward the outer end, so the canopy interior stays
      // open the way a self-shaded canopy is.
      final along = math
          .pow(rng.unit(), 1.0 - rules.canopyBias * 0.6)
          .toDouble()
          .clamp(0.0, 1.0);
      final base = branch.pointAt(0.12 + 0.88 * along);
      final spread = radius * math.sqrt(rng.unit());
      final pos = base + Vec2.fromAngle(rng.range(0, math.pi * 2), spread);

      leaves.add(
        Leaf(
          position: base.lerpTo(pos, openness),
          angle: rng.range(-math.pi, math.pi),
          scale: rules.leafSize * rng.range(0.68, 1.32) * openness,
          tone: rng.unit(),
          phase: rng.range(0, math.pi * 2),
          depth: along,
        ),
      );
    }

    return LeafCluster(
      anchor: branch.pointAt(0.7),
      radius: radius,
      leaves: leaves,
      openness: openness,
      branchIndex: branchIndex,
    );
  }
}

Vec2 _directionAtDistance(MatureBranch b, double distance) {
  for (var i = 1; i < b.cumulative.length; i++) {
    if (b.cumulative[i] >= distance) {
      return (b.spine[i] - b.spine[i - 1]).normalized;
    }
  }
  return (b.spine.last - b.spine[b.spine.length - 2]).normalized;
}

double _widthAtFraction(MatureBranch b, double fraction) =>
    b.widthBase + (b.widthTip - b.widthBase) * fraction;

double _easeOut(double t) => 1 - math.pow(1 - t, 2.2).toDouble();

double _signedAngleBetween(Vec2 from, Vec2 to) =>
    math.atan2(from.x * to.y - from.y * to.x, from.x * to.x + from.y * to.y);

/// A stable identity for a branch: the parent's id with the child index mixed
/// in, so identity depends on position in the tree and nothing else.
int _childId(int parentId, int childIndex) =>
    (parentId * 17 + childIndex + 1) & 0x3FFFFFFF;

int _branchSeed(int treeSeed, int branchId) {
  var h = treeSeed ^ (branchId * 0x9E3779B1);
  h ^= h >>> 15;
  h = (h * 0x85EBCA6B) & 0xFFFFFFFF;
  h ^= h >>> 13;
  return h & 0xFFFFFFFF;
}

/// Seeded generator. `grow_flora` must never use unseeded randomness: a tree
/// that reshuffles itself between frames is not an individual.
class _Rng {
  _Rng(int seed) : _s = (seed == 0 ? 0x9E3779B9 : seed) & 0xFFFFFFFF;
  int _s;

  int _next() {
    _s ^= (_s << 13) & 0xFFFFFFFF;
    _s ^= _s >>> 17;
    _s ^= (_s << 5) & 0xFFFFFFFF;
    _s &= 0xFFFFFFFF;
    return _s;
  }

  double unit() => _next() / 4294967296.0;
  double range(double a, double b) => a + unit() * (b - a);
  bool chance(double p) => unit() < p;
}
