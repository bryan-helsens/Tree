import 'package:flutter/widgets.dart';
import 'package:grow_domain/grow_domain.dart';
import 'package:grow_flora/grow_flora.dart';

import 'canopy_atlas.dart';
import 'care_effect.dart';
import 'forest_scene.dart';
import 'tree_painter.dart';

/// What the view needs to know about one tree. Mirrors `TreeVisual` from the
/// simulation without `grow_render` depending on `grow_sim`: the application
/// layer maps one to the other.
class ForestTree {
  const ForestTree({
    required this.id,
    required this.skeleton,
    required this.form,
    required this.foliage,
    required this.groundX,
    required this.depth,
    required this.seed,
    required this.semanticLabel,
    required this.semanticValue,
    this.timesWatered = 0,
    this.timesFed = 0,
  });

  final TreeId id;
  final TreeSkeleton skeleton;
  final SpeciesForm form;
  final FoliageState foliage;
  final double groundX;
  final double depth;
  final int seed;

  /// Built by the simulation layer, next to the numbers it describes.
  final String semanticLabel;
  final String semanticValue;

  /// Domain counters. The renderer plays a care burst when one of these
  /// increments — the animation follows the state, not the button.
  final int timesWatered;
  final int timesFed;
}

/// The living world, with an accessible parallel to it.
///
/// A canvas is invisible to a screen reader: everything drawn here would be
/// one unlabelled rectangle. So every tree also gets a real `Semantics` node,
/// positioned over where it is drawn, carrying the description the simulation
/// produced and responding to the same tap.
///
/// Built alongside the visuals rather than retrofitted, because the geometry
/// that places a tree is the same geometry that places its semantic node —
/// splitting them in time means computing it twice and letting them disagree.
class ForestView extends StatelessWidget {
  const ForestView({
    required this.trees,
    required this.conditions,
    required this.timeOfDay01,
    required this.timeSeconds,
    required this.worldSeed,
    this.atlas,
    this.quality = RenderQuality.high,
    this.windAmplitude = 1.0,
    this.onTapTree,
    super.key,
  });

  final List<ForestTree> trees;
  final WorldConditions conditions;
  final double timeOfDay01;
  final double timeSeconds;
  final int worldSeed;
  final CanopyAtlas? atlas;
  final RenderQuality quality;
  final double windAmplitude;
  final void Function(TreeId)? onTapTree;

  /// Touch targets never fall below this, however small the tree is drawn.
  static const double minimumTapTarget = 48;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: CustomPaint(
                painter: _ScenePainter(
                  trees: trees,
                  conditions: conditions,
                  timeOfDay01: timeOfDay01,
                  timeSeconds: timeSeconds,
                  worldSeed: worldSeed,
                  atlas: atlas,
                  quality: quality,
                  // Reduced motion keeps the world alive but still: the world
                  // going completely static removes the thing a player is
                  // here for.
                  windAmplitude: reduceMotion
                      ? windAmplitude * 0.15
                      : windAmplitude,
                ),
                size: size,
              ),
            ),
            for (final tree in trees) _careEffect(tree, size),
            for (final tree in trees) _hitTarget(tree, size),
          ],
        );
      },
    );
  }

  Widget _careEffect(ForestTree tree, Size size) {
    final rect = treeRect(tree, size);
    return Positioned.fromRect(
      rect: rect,
      child: CareEffect(
        // Keyed by tree so a rebuild that reorders the list cannot hand one
        // tree's effect state to another.
        key: ValueKey('care-${tree.id.raw}'),
        waterCount: tree.timesWatered,
        feedCount: tree.timesFed,
        size: rect.size,
      ),
    );
  }

  Widget _hitTarget(ForestTree tree, Size size) {
    final rect = treeRect(tree, size);
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: Semantics(
        label: tree.semanticLabel,
        value: tree.semanticValue,
        button: true,
        // Screen readers announce a container as one node; without this the
        // canvas behind would swallow it.
        container: true,
        onTap: onTapTree == null ? null : () => onTapTree!(tree.id),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTapTree == null ? null : () => onTapTree!(tree.id),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  /// Where a tree is drawn, in view coordinates.
  ///
  /// Shared by the painter and the semantics/hit layer so they cannot drift,
  /// and expanded to at least [minimumTapTarget] in both axes — a seedling is
  /// only a few pixels tall but still has to be reachable.
  static Rect treeRect(ForestTree tree, Size size) {
    // The same call the painter makes. Not a copy of it.
    final where = ForestScene.placeTree(size, tree.groundX, tree.depth);
    final b = tree.skeleton.bounds;

    var rect = Rect.fromLTRB(
      where.x + b.minX * where.scale,
      where.baseY + b.minY * where.scale,
      where.x + b.maxX * where.scale,
      where.baseY,
    );
    if (rect.width < minimumTapTarget) {
      rect = Rect.fromCenter(
        center: rect.center,
        width: minimumTapTarget,
        height: rect.height,
      );
    }
    if (rect.height < minimumTapTarget) {
      rect = Rect.fromCenter(
        center: rect.center,
        width: rect.width,
        height: minimumTapTarget,
      );
    }
    return rect;
  }
}

class _ScenePainter extends CustomPainter {
  const _ScenePainter({
    required this.trees,
    required this.conditions,
    required this.timeOfDay01,
    required this.timeSeconds,
    required this.worldSeed,
    required this.atlas,
    required this.quality,
    required this.windAmplitude,
  });

  final List<ForestTree> trees;
  final WorldConditions conditions;
  final double timeOfDay01;
  final double timeSeconds;
  final int worldSeed;
  final CanopyAtlas? atlas;
  final RenderQuality quality;
  final double windAmplitude;

  @override
  void paint(Canvas canvas, Size size) {
    ForestScene(atlas: atlas, quality: quality).paint(
      canvas,
      size,
      trees: [
        for (final t in trees)
          TreePlacement(
            id: t.id,
            groundX: t.groundX,
            depth: t.depth,
            skeleton: t.skeleton,
            form: t.form,
            foliage: t.foliage,
            seed: t.seed,
          ),
      ],
      conditions: conditions,
      timeOfDay01: timeOfDay01,
      timeSeconds: timeSeconds,
      worldSeed: worldSeed,
      windAmplitude: windAmplitude,
    );
  }

  @override
  bool shouldRepaint(_ScenePainter old) =>
      old.timeSeconds != timeSeconds ||
      old.trees != trees ||
      old.conditions != conditions ||
      old.timeOfDay01 != timeOfDay01;
}
