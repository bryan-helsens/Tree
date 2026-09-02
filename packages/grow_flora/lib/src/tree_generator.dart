import 'dart:math' as math;

import 'branch_rules.dart';
import 'tree_skeleton.dart';
import 'vec2.dart';

/// Generates a tree's form from `(rules, seed, growth01)`.
///
/// Deterministic: the same three inputs always produce the same tree, which is
/// what lets an individual keep its identity for the life of a save while
/// still differing from every other tree of its species.
///
/// Growth is continuous. Nothing pops: branches unfurl over a window, the
/// trunk thickens, and the silhouette genuinely changes shape between stages.
class TreeGenerator {
  const TreeGenerator();

  static const double _emergeWindow = 0.12;

  TreeSkeleton generate({
    required BranchRules rules,
    required int seed,
    required double growth01,
  }) {
    final g = growth01.clamp(0.0, 1.0).toDouble();

    // Height rises quickly at first and then slows, so early care feels
    // responsive and late growth feels earned.
    final scale = math.pow(g, 0.55).toDouble();
    // Thickening lags extension, which is how real trunks behave and why an
    // old tree reads as old rather than merely large.
    final widthScale = math.pow(g, 0.78).toDouble();

    final branches = <Branch>[];

    final trunk = _growBranch(
      rules: rules,
      rng: _Rng(_branchSeed(seed, 1)),
      start: Vec2.zero,
      direction: const Vec2(0, -1),
      length: rules.trunkLength * scale,
      widthBase: rules.trunkWidth * widthScale,
      widthTip: rules.trunkWidth * rules.taper * widthScale,
      depth: 0,
      emergeAt: 0,
      sinuosity: rules.trunkSinuosity,
      parentIndex: -1,
      branchId: 1,
    );
    branches.add(trunk);

    _branchFrom(
      rules: rules,
      seed: seed,
      parentId: 1,
      parent: trunk,
      parentIndex: 0,
      depth: 1,
      growth01: g,
      scale: scale,
      widthScale: widthScale,
      branches: branches,
    );

    // Keep only what has emerged at this growth value.
    final visible = <Branch>[];
    final sourceIndex = <int>[];
    final hasVisibleChild = List<bool>.filled(branches.length, false);
    // How far along each branch's children are. A parent hands its foliage
    // over as they emerge rather than switching the instant they appear.
    final childEmergence = List<double>.filled(branches.length, 0);
    for (var i = 0; i < branches.length; i++) {
      final b = branches[i];
      if (g < b.emergeAt) continue;
      final t = ((g - b.emergeAt) / _emergeWindow).clamp(0.0, 1.0);
      if (b.parentIndex >= 0) {
        hasVisibleChild[b.parentIndex] = true;
        if (t > childEmergence[b.parentIndex]) {
          childEmergence[b.parentIndex] = t;
        }
      }
      visible.add(t >= 1.0 ? b : _partial(b, _easeOut(t)));
      sourceIndex.add(i);
    }

    // Leaves grow on terminal shoots — whatever is currently outermost.
    //
    // Attaching them by fixed depth instead leaves a seedling as a bare stick
    // until it is old enough to reach that depth, which is both botanically
    // wrong and the least appealing possible first impression.
    final visibleClusters = <LeafCluster>[];
    var maxVisibleDepth = 0;
    for (final b in visible) {
      if (b.depth > maxVisibleDepth) maxVisibleDepth = b.depth;
    }

    for (var vi = 0; vi < visible.length; vi++) {
      final src = sourceIndex[vi];
      final b = visible[vi];
      final terminal = !hasVisibleChild[src];
      // Foliage sits on the terminal shoots and on the outer structure that
      // carries them. Terminal-only leaves ball up at the tips and read as
      // pom-poms on bare sticks; carrying them one generation inward is what
      // closes the canopy into a mass.
      final carrier = b.depth >= maxVisibleDepth - 1;
      if (!terminal && !carrier) continue;

      // A branch whose children are still unfurling keeps its own leaves,
      // fading them out as the children take over. Switching the moment a
      // child appears makes the canopy jump inward and the whole tree
      // visibly shrink — the exact pop continuous growth is meant to avoid.
      final handover = 1.0 - childEmergence[src];
      final density = terminal
          ? 1.0
          : (0.55 + 0.45 * handover).clamp(0.0, 1.0).toDouble();

      final emergeAt = b.emergeAt;
      final t = ((g - emergeAt) / (_emergeWindow * 1.6)).clamp(0.0, 1.0);
      if (t <= 0.02) continue;
      visibleClusters.add(
        _leafCluster(
          rules: rules,
          rng: _Rng(_branchSeed(seed, b.branchId ^ 0x5BF03635)),
          branch: b,
          branchIndex: vi,
          emergeAt: emergeAt,
          growth01: g,
          openness: _easeOut(t),
          density: density,
        ),
      );
    }

    final points = [
      for (final b in visible) ...b.spine,
      for (final c in visibleClusters)
        for (final l in c.leaves) l.position,
    ];

    return TreeSkeleton(
      branches: visible,
      clusters: visibleClusters,
      bounds: Bounds.around(points.isEmpty ? [Vec2.zero] : points),
      growth01: g,
      trunkBase: Vec2.zero,
    );
  }

  // ─── recursion ─────────────────────────────────────────────────────────

  void _branchFrom({
    required BranchRules rules,
    required int seed,
    required int parentId,
    required Branch parent,
    required int parentIndex,
    required int depth,
    required double growth01,
    required double scale,
    required double widthScale,
    required List<Branch> branches,
  }) {
    if (depth > rules.maxDepth) {
      return;
    }

    // Each branch draws from its own generator, keyed to a stable identity in
    // the tree rather than to a position in one long shared sequence.
    //
    // With a single threaded generator, anything that changes how many random
    // numbers an earlier branch consumes reshuffles every branch after it —
    // and step count depends on branch length, which depends on growth. The
    // tree would silently reshape itself as it grew instead of growing.
    final rng = _Rng(_branchSeed(seed, parentId));
    final childCount = rules.childrenPerBranch;
    // Deeper structure appears later, so the tree gains complexity as it ages
    // rather than merely scaling up.
    final emergeAt =
        (depth / (rules.maxDepth + 1.0)) * 0.78 + rng.range(-0.03, 0.03);

    // Alternate sides, with enough jitter that it never reads as a zip.
    var side = rng.chance(0.5) ? 1.0 : -1.0;

    for (var i = 0; i < childCount; i++) {
      // Children spawn along the upper part of the parent; the span below
      // firstNodeAt stays clean.
      final span = 1.0 - rules.firstNodeAt;
      final t =
          rules.firstNodeAt +
          span * ((i + 0.5) / childCount) +
          rng.range(-0.05, 0.05);
      final tc = t.clamp(0.05, 0.98).toDouble();

      final origin = parent.pointAt(tc);
      final parentDir = parent.directionAt(tc);

      // Angles narrow with depth, so successive generations turn back toward
      // vertical and the canopy closes into a dome instead of spreading flat.
      final decay = rules.angleRangeAt(depth - 1);
      final angle =
          (rng.range(rules.branchAngleMinRad, rules.branchAngleMaxRad) +
              rng.range(-rules.angleJitterRad, rules.angleJitterRad)) *
          decay;
      final sided =
          angle * side * (1.0 + rng.range(-rules.asymmetry, rules.asymmetry));
      final direction = parentDir.rotated(sided);

      final lengthFactor = rules.lengthDecay * rng.range(0.82, 1.18);
      final childLength = parent.length * lengthFactor;
      final wBase = parent.widthAt(tc) * rules.taper;

      final childId = _childId(parentId, i);
      final child = _growBranch(
        rules: rules,
        rng: _Rng(_branchSeed(seed, childId)),
        start: origin,
        direction: direction,
        length: childLength,
        widthBase: wBase,
        widthTip: wBase * rules.taper,
        depth: depth,
        emergeAt: emergeAt,
        sinuosity: rules.trunkSinuosity * 0.6,
        parentIndex: parentIndex,
        branchId: childId,
      );
      final childIndex = branches.length;
      branches.add(child);

      _branchFrom(
        rules: rules,
        seed: seed,
        parentId: childId,
        parent: child,
        parentIndex: childIndex,
        depth: depth + 1,
        growth01: growth01,
        scale: scale,
        widthScale: widthScale,
        branches: branches,
      );

      side = -side;
    }

    // Apical extension: the parent continues past its last child. Without
    // this a tree is a bush of even forks; with it, it has a leader.
    if (depth <= rules.maxDepth && rules.apicalExtension > 0.01) {
      final tipDir = parent.directionAt(1.0);
      final leaderLength =
          parent.length * rules.apicalExtension * rng.range(0.85, 1.15);
      final wBase = parent.widthTip;
      final leaderId = _childId(parentId, 15);
      final leader = _growBranch(
        rules: rules,
        rng: _Rng(_branchSeed(seed, leaderId)),
        start: parent.tip,
        direction: tipDir,
        length: leaderLength,
        widthBase: wBase,
        widthTip: wBase * rules.taper,
        depth: depth,
        emergeAt: emergeAt,
        sinuosity: rules.trunkSinuosity * 0.5,
        parentIndex: parentIndex,
        branchId: leaderId,
      );
      final leaderIndex = branches.length;
      branches.add(leader);

      _branchFrom(
        rules: rules,
        seed: seed,
        parentId: leaderId,
        parent: leader,
        parentIndex: leaderIndex,
        depth: depth + 1,
        growth01: growth01,
        scale: scale,
        widthScale: widthScale,
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
  Branch _growBranch({
    required BranchRules rules,
    required _Rng rng,
    required Vec2 start,
    required Vec2 direction,
    required double length,
    required double widthBase,
    required double widthTip,
    required int depth,
    required double emergeAt,
    required double sinuosity,
    required int parentIndex,
    required int branchId,
  }) {
    // Fixed per depth, deliberately not derived from length: a growth-varying
    // step count would change how many random draws this branch makes and
    // reshape it as the tree grew.
    final steps = (12 - depth).clamp(4, 12);
    final stepLength = length / steps;
    final spine = <Vec2>[start];

    var pos = start;
    var dir = direction.normalized;
    final thinness =
        1.0 - (widthBase / (rules.trunkWidth + 0.001)).clamp(0.0, 1.0);

    for (var i = 0; i < steps; i++) {
      final t = (i + 1) / steps;

      // Light: rotate the direction toward straight up.
      const up = Vec2(0, -1);
      final toUp = _signedAngleBetween(dir, up);
      final photo = toUp * rules.phototropism * 0.16 * (0.35 + 0.65 * thinness);

      // Gravity: sag grows along the branch and with thinness.
      final droop =
          rules.gravityDroop * 0.18 * t * thinness * (dir.x >= 0 ? 1.0 : -1.0);

      final noise =
          rng.range(-1.0, 1.0) * rules.wobble * 0.14 +
          rng.range(-1.0, 1.0) * sinuosity * 0.10;

      dir = dir.rotated(photo + droop + noise).normalized;
      pos = pos + dir * stepLength;
      spine.add(pos);
    }

    return Branch(
      spine: spine,
      widthBase: widthBase,
      widthTip: widthTip,
      depth: depth,
      emergeAt: emergeAt.clamp(0.0, 1.0).toDouble(),
      phase: rng.range(0, math.pi * 2),
      // Thin branches move most. One expression drives every twig in the
      // world's response to the shared wind field.
      flex: (1.0 / (widthBase + 0.6)).clamp(0.0, 3.0).toDouble(),
      parentIndex: parentIndex,
      branchId: branchId,
    );
  }

  LeafCluster _leafCluster({
    required BranchRules rules,
    required _Rng rng,
    required Branch branch,
    required int branchIndex,
    required double emergeAt,
    required double growth01,
    double openness = 1.0,
    double density = 1.0,
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
      // Bias placement toward the outer end of the branch, so the canopy
      // interior stays open the way a self-shaded canopy is.
      final along = math
          .pow(rng.unit(), 1.0 - rules.canopyBias * 0.6)
          .toDouble()
          .clamp(0.0, 1.0);
      // Spread along most of the shoot, not just its last third.
      final base = branch.pointAt(0.12 + 0.88 * along);
      final spread = radius * math.sqrt(rng.unit());
      final theta = rng.range(0, math.pi * 2);
      final pos = base + Vec2.fromAngle(theta, spread);

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
      emergeAt: emergeAt.clamp(0.0, 1.0).toDouble(),
      branchIndex: branchIndex,
    );
  }

  Branch _partial(Branch b, double t) {
    final target = b.length * t;
    final spine = <Vec2>[b.spine.first];
    var acc = 0.0;
    for (var i = 1; i < b.spine.length; i++) {
      final seg = (b.spine[i] - b.spine[i - 1]).length;
      if (acc + seg >= target) {
        final r = seg == 0 ? 0.0 : (target - acc) / seg;
        spine.add(b.spine[i - 1].lerpTo(b.spine[i], r));
        break;
      }
      acc += seg;
      spine.add(b.spine[i]);
    }
    if (spine.length < 2) spine.add(b.spine.first + const Vec2(0, -0.5));
    return Branch(
      spine: spine,
      widthBase: b.widthBase,
      widthTip:
          (b.widthBase + (b.widthTip - b.widthBase) * t) * (0.25 + 0.75 * t),
      depth: b.depth,
      emergeAt: b.emergeAt,
      phase: b.phase,
      flex: b.flex,
      parentIndex: b.parentIndex,
      branchId: b.branchId,
    );
  }
}

/// A stable identity for a branch: the parent's id with the child index mixed
/// in, so a branch's identity depends on where it sits in the tree and nothing
/// else.
int _childId(int parentId, int childIndex) =>
    (parentId * 17 + childIndex + 1) & 0x3FFFFFFF;

int _branchSeed(int treeSeed, int branchId) {
  var h = treeSeed ^ (branchId * 0x9E3779B1);
  h ^= h >>> 15;
  h = (h * 0x85EBCA6B) & 0xFFFFFFFF;
  h ^= h >>> 13;
  return h & 0xFFFFFFFF;
}

double _easeOut(double t) => 1 - math.pow(1 - t, 2.2).toDouble();

double _signedAngleBetween(Vec2 from, Vec2 to) {
  final a = math.atan2(
    from.x * to.y - from.y * to.x,
    from.x * to.x + from.y * to.y,
  );
  return a;
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
