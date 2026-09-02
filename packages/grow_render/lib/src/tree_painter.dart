import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:grow_flora/grow_flora.dart';

import 'canopy_atlas.dart';

/// Draws a generated tree onto a Canvas.
///
/// Everything here is derived: branch shape from the skeleton, colour from the
/// palette and the tree's condition, movement from the shared wind field.
/// There are no per-state drawings, which is the whole point of the approach.
class TreeRenderer {
  const TreeRenderer({
    this.wind = const WindField(),
    this.quality = RenderQuality.high,
    this.atlas,
  });

  final WindField wind;
  final RenderQuality quality;

  /// How many overlapping sprites each foliage cluster contributes.
  static const int _spritesPerCluster = 3;

  /// The canopy sprite atlas. When present the canopy is drawn as a single
  /// batched `drawAtlas` call; without it the renderer falls back to
  /// individual leaf paths, which is correct but far more expensive.
  final CanopyAtlas? atlas;

  void paint(
    Canvas canvas,
    TreeSkeleton tree, {
    required SpeciesForm form,
    required FoliageState state,
    required double timeSeconds,
    Offset origin = Offset.zero,
  }) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);

    _paintBranches(canvas, tree, form, state, timeSeconds);
    if (atlas != null) {
      _paintCanopyBatched(canvas, tree, form, state, timeSeconds, atlas!);
    } else {
      _paintCanopy(canvas, tree, form, state, timeSeconds);
    }
    if (state.sparkle > 0.45 && quality != RenderQuality.low) {
      _paintSparkle(canvas, tree, state, timeSeconds);
    }
    canvas.restore();
  }

  // ─── woody structure ───────────────────────────────────────────────────

  void _paintBranches(
    Canvas canvas,
    TreeSkeleton tree,
    SpeciesForm form,
    FoliageState state,
    double t,
  ) {
    // Back to front by depth, so thin twigs sit over the trunk.
    final ordered = [...tree.branches]
      ..sort((a, b) => a.depth.compareTo(b.depth));

    for (final b in ordered) {
      final sway =
          wind.swayFor(t, b.base.y, b.phase, b.flex) *
          (1.0 - state.wetness * 0.4);
      final path = _branchPath(b, sway, state);
      // Lighter toward the tips: aerial perspective inside the canopy.
      final tone = (b.depth / (form.rules.maxDepth + 1)).clamp(0.0, 1.0);
      final bark = Color(form.palette.barkColor(tone, state));
      canvas.drawPath(
        path,
        Paint()
          ..color = bark
          ..style = PaintingStyle.fill
          ..isAntiAlias = true,
      );

      // A lit edge down one side. One extra stroke, and the trunk stops
      // reading as a cut-out.
      if (quality != RenderQuality.low && b.widthBase > 2.2) {
        canvas.drawPath(
          _branchPath(b, sway, state, inset: b.widthBase * 0.30),
          Paint()
            ..color = _lighten(bark, 0.16).withValues(alpha: 0.55)
            ..style = PaintingStyle.fill
            ..isAntiAlias = true,
        );
      }
    }
  }

  /// A tapered ribbon along the branch spine.
  ///
  /// Drawing branches as filled outlines rather than stroked lines is what
  /// lets a trunk actually taper, which is most of the difference between a
  /// tree and a stick figure.
  Path _branchPath(
    Branch b,
    double sway,
    FoliageState state, {
    double inset = 0,
  }) {
    final left = <Offset>[];
    final right = <Offset>[];
    final n = b.spine.length;

    for (var i = 0; i < n; i++) {
      final t = i / (n - 1);
      final p = b.spine[i];

      // Sway accumulates along the branch, and drooping adds downward bias.
      final bend = sway * t * t;
      final droop = state.droop * 7.0 * t * t * b.flex.clamp(0, 1.2);
      final pos = Offset(p.x + bend, p.y + droop);

      final dir = b.directionAt(t);
      final normal = Offset(-dir.y, dir.x);
      final w = b.widthAt(t) / 2;
      // A non-zero inset produces a narrower ribbon offset to one side, used
      // for the lit edge. Both halves are clamped above zero: letting either
      // go negative flips the ribbon and cuts a bright notch out of the trunk.
      final outer = math.max(0.15, w - inset);
      final inner = math.max(0.05, w - inset * 2.4);
      left.add(pos + normal * outer);
      right.add(pos - normal * inner);
    }

    final path = Path()..moveTo(left.first.dx, left.first.dy);
    for (final p in left.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    for (final p in right.reversed) {
      path.lineTo(p.dx, p.dy);
    }
    path.close();
    return path;
  }

  // ─── canopy, batched ───────────────────────────────────────────────────

  /// One `drawAtlas` call for the whole canopy.
  ///
  /// Each cluster becomes one sprite: an `RSTransform` for where and how big,
  /// a source rect for which tile, and a colour that carries the tint. With
  /// `BlendMode.modulate` against luminance-only tiles, the health uniforms
  /// still drive every pixel of colour — the sprite supplies shape and
  /// shading, the simulation supplies the hue.
  ///
  /// This replaces thousands of individual leaf paths with a single draw, and
  /// it is why the atlas is part of the architecture rather than a later
  /// optimisation.
  void _paintCanopyBatched(
    Canvas canvas,
    TreeSkeleton tree,
    SpeciesForm form,
    FoliageState state,
    double t,
    CanopyAtlas atlas,
  ) {
    if (state.bareness >= 0.98 || tree.clusters.isEmpty) return;

    final transforms = <RSTransform>[];
    final rects = <Rect>[];
    final colours = <Color>[];

    final cap = quality.spriteCap;
    final stride = tree.clusters.length > cap
        ? (tree.clusters.length / cap).ceil()
        : 1;

    for (var i = 0; i < tree.clusters.length; i += stride) {
      final c = tree.clusters[i];
      if (c.openness <= 0.02 || c.leaves.isEmpty) continue;
      // Thinning at high bareness drops whole clumps rather than dimming
      // them, which is how a canopy actually empties.
      if (state.bareness > 0 && (i % 7) / 7.0 < state.bareness) continue;

      final sway =
          wind.swayFor(t, c.anchor.y, c.branchIndex * 0.7, 1.5) *
          (1.0 - state.wetness * 0.45);
      final droop = state.droop * 9.0;

      // Several small overlapping sprites per cluster rather than one large
      // one. A single sprite per cluster reads as a row of separate spheres;
      // overlapping them is what merges the canopy into one crown.
      //
      // The leaf positions already computed for the cluster make good
      // anchors: they are distributed along and around the branch, so no
      // extra placement work is needed.
      final perCluster = math.min(_spritesPerCluster, c.leaves.length);
      final leafStride = (c.leaves.length / perCluster).ceil();

      for (var k = 0; k < c.leaves.length; k += leafStride) {
        final anchor = c.leaves[k];
        final size = c.radius * 1.55;
        final tile =
            ((c.branchIndex * 2654435761) + k * 40503) % atlas.tileCount;
        // Rotation varies per sprite so a repeated tile is not readable.
        final rotation =
            (((c.branchIndex * 37 + k * 91) % 360) * math.pi / 180) +
            sway * 0.02;

        transforms.add(
          RSTransform.fromComponents(
            rotation: rotation,
            scale: size / atlas.tileSize,
            anchorX: atlas.tileSize / 2,
            anchorY: atlas.tileSize / 2,
            translateX: anchor.position.x + sway * 2.2,
            translateY: anchor.position.y + droop,
          ),
        );
        rects.add(atlas.tileRect(tile));

        // Outer foliage catches the light; the interior sits back.
        final shade = 0.80 + 0.20 * anchor.depth;
        colours.add(
          _scale(form.palette.leafColor(anchor.tone, state), shade).withValues(
            alpha: (c.openness * (1.0 - state.bareness * 0.4)).clamp(0.0, 1.0),
          ),
        );
      }
    }

    if (transforms.isEmpty) return;
    canvas.drawAtlas(
      atlas.image,
      transforms,
      rects,
      colours,
      BlendMode.modulate,
      null,
      Paint()..isAntiAlias = true,
    );

    if (state.flowering > 0.05) {
      _paintBlossom(canvas, tree, form, state, t);
    }
  }

  // ─── canopy, unbatched fallback ────────────────────────────────────────

  void _paintCanopy(
    Canvas canvas,
    TreeSkeleton tree,
    SpeciesForm form,
    FoliageState state,
    double t,
  ) {
    if (state.bareness >= 0.98) return;
    final cap = quality.leafCap;
    var drawn = 0;

    // The canopy is closed by leaf density now, not by a blurred underlay.
    // A blur behind the foliage bleeds a soft halo past the silhouette, which
    // reads as a glow effect rather than as leaves.

    // Depth-sorted so interior leaves sit behind outer ones, which reads as
    // canopy volume rather than a flat sticker.
    final all = <({Leaf leaf, LeafCluster cluster})>[];
    for (final c in tree.clusters) {
      for (final l in c.leaves) {
        all.add((leaf: l, cluster: c));
      }
    }
    all.sort((a, b) => a.leaf.depth.compareTo(b.leaf.depth));

    final stride = all.length > cap ? (all.length / cap).ceil() : 1;

    for (var i = 0; i < all.length; i += stride) {
      final leaf = all[i].leaf;
      if (state.bareness > 0 && leaf.tone < state.bareness) continue;

      final sway =
          wind.swayFor(t, leaf.position.y, leaf.phase, 1.6) *
          (1.0 - state.wetness * 0.45);
      final droop = state.droop * 9.0;

      final centre = Offset(
        leaf.position.x + sway * 2.2,
        leaf.position.y + droop,
      );

      // Interior leaves sit in deep shade, outer ones catch the light. The
      // contrast is what turns a flat mass into a canopy with a near and a
      // far side.
      final shade = 0.58 + 0.46 * leaf.depth;
      final base = form.palette.leafColor(leaf.tone, state);
      final colour = _scale(base, shade);

      _paintLeaf(
        canvas,
        centre,
        leaf.angle + sway * 0.10 + state.droop * 0.5,
        leaf.scale * (1.0 - state.droop * 0.08),
        colour,
      );
      drawn++;
      if (drawn >= cap) break;
    }

    if (state.flowering > 0.05) {
      _paintBlossom(canvas, tree, form, state, t);
    }
  }

  /// A leaf is a two-arc lens, not a circle. It costs the same and it is the
  /// difference between foliage and a spray of dots.
  void _paintLeaf(
    Canvas canvas,
    Offset centre,
    double angle,
    double scale,
    Color colour,
  ) {
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(angle);

    final w = scale, h = scale * 1.55;
    final path = Path()
      ..moveTo(0, -h / 2)
      ..quadraticBezierTo(w * 0.72, -h * 0.06, 0, h / 2)
      ..quadraticBezierTo(-w * 0.72, -h * 0.06, 0, -h / 2)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = colour
        ..isAntiAlias = true,
    );
    canvas.restore();
  }

  void _paintBlossom(
    Canvas canvas,
    TreeSkeleton tree,
    SpeciesForm form,
    FoliageState state,
    double t,
  ) {
    final paint = Paint()
      ..color = Color(
        form.palette.flowerColor,
      ).withValues(alpha: state.flowering.clamp(0.0, 1.0))
      ..isAntiAlias = true;
    for (final c in tree.clusters) {
      for (var i = 0; i < c.leaves.length; i += 6) {
        final l = c.leaves[i];
        final sway = wind.swayFor(t, l.position.y, l.phase, 1.4);
        canvas.drawCircle(
          Offset(l.position.x + sway * 2, l.position.y),
          l.scale * 0.42,
          paint,
        );
      }
    }
  }

  void _paintSparkle(
    Canvas canvas,
    TreeSkeleton tree,
    FoliageState state,
    double t,
  ) {
    if (tree.clusters.isEmpty) return;
    final paint = Paint()
      ..color = const Color(0xFFF2E3AE).withValues(alpha: 0.85)
      ..isAntiAlias = true
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6);

    // Two or three slow motes at most, and only well above the threshold, so
    // seeing one means the tree really is doing well.
    final count = (3 * state.sparkle).round();
    for (var i = 0; i < count; i++) {
      final c = tree.clusters[(i * 7) % tree.clusters.length];
      final cycle = (t * 0.35 + i * 0.37) % 1.0;
      final rise = -18.0 * cycle;
      final alpha = math.sin(cycle * math.pi);
      canvas.drawCircle(
        Offset(c.anchor.x + math.sin(t * 0.9 + i) * 5, c.anchor.y + rise),
        0.9 + alpha * 0.5,
        paint..color = const Color(0xFFF2E3AE).withValues(alpha: alpha * 0.55),
      );
    }
  }

  static Color _lighten(Color c, double f) => Color.fromARGB(
    255,
    (c.r * 255 + (255 - c.r * 255) * f).clamp(0, 255).round(),
    (c.g * 255 + (255 - c.g * 255) * f).clamp(0, 255).round(),
    (c.b * 255 + (255 - c.b * 255) * f).clamp(0, 255).round(),
  );

  static Color _scale(int argb, double f) => Color.fromARGB(
    255,
    (((argb >> 16) & 0xFF) * f).clamp(0, 255).round(),
    (((argb >> 8) & 0xFF) * f).clamp(0, 255).round(),
    ((argb & 0xFF) * f).clamp(0, 255).round(),
  );
}

enum RenderQuality {
  low(leafCap: 260, spriteCap: 40),
  medium(leafCap: 1100, spriteCap: 110),
  high(leafCap: 2600, spriteCap: 260);

  const RenderQuality({required this.leafCap, required this.spriteCap});

  /// Ceiling on individual leaf paths, for the unbatched fallback path.
  final int leafCap;

  /// Ceiling on canopy sprites per tree. These all go in one draw call, so
  /// this can be far more generous than [leafCap].
  final int spriteCap;
}

/// Ground, soil and its response to moisture. Kept next to the tree because
/// wet soil is one of the main ways the player reads overwatering.
class GroundRenderer {
  const GroundRenderer();

  void paint(
    Canvas canvas,
    Rect area, {
    required FoliageState state,
    required double timeSeconds,
    int soilDry = 0xFF6B5744,
    int soilWet = 0xFF3A2C20,
    int grass = 0xFF54703C,
  }) {
    final soil = Color.lerp(
      Color(soilDry),
      Color(soilWet),
      state.wetness.clamp(0.0, 1.0),
    )!;

    canvas.drawRect(area, Paint()..color = soil);

    // A soft mound under the trunk rather than a hard horizon line.
    final mound = Path()
      ..moveTo(area.left, area.top + 10)
      ..quadraticBezierTo(
        area.center.dx,
        area.top - 10,
        area.right,
        area.top + 10,
      )
      ..lineTo(area.right, area.bottom)
      ..lineTo(area.left, area.bottom)
      ..close();
    canvas.drawPath(mound, Paint()..color = soil);

    if (state.wetness > 0.55) {
      // Standing water: the clearest possible read that a tree is drowning.
      final puddle = Paint()
        ..color = const Color(
          0xFF2A3B44,
        ).withValues(alpha: (state.wetness - 0.55) * 1.2)
        ..isAntiAlias = true;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(area.center.dx - 22, area.top + 16),
          width: 54,
          height: 13,
        ),
        puddle,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(area.center.dx + 30, area.top + 24),
          width: 34,
          height: 9,
        ),
        puddle,
      );
    }

    _paintGrass(canvas, area, grass, state, timeSeconds);
  }

  void _paintGrass(
    Canvas canvas,
    Rect area,
    int colour,
    FoliageState state,
    double t,
  ) {
    const wind = WindField();
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    for (var i = 0; i < 90; i++) {
      final x = area.left + (i * 37 % area.width);
      final h = 7.0 + (i * 13 % 11);
      final y = area.top + 4 + (i * 7 % 14);
      // Grass reads from the same wind field as the canopy, which is why the
      // scene moves as one place rather than as separate loops.
      final lean = wind.at(t, y) * 2.4 * (h / 12);
      final shade = 0.78 + (i % 5) * 0.055;
      paint
        ..color = Color.fromARGB(
          255,
          (((colour >> 16) & 0xFF) * shade).round().clamp(0, 255),
          (((colour >> 8) & 0xFF) * shade).round().clamp(0, 255),
          ((colour & 0xFF) * shade).round().clamp(0, 255),
        )
        ..strokeWidth = 1.4;
      canvas.drawPath(
        Path()
          ..moveTo(x, y)
          ..quadraticBezierTo(x + lean * 0.5, y - h * 0.6, x + lean, y - h),
        paint,
      );
    }
  }
}

/// Renders a tree to a PNG. Used by the export tool and by golden tests, so
/// what is reviewed is what the game actually draws.
Future<ui.Image> renderTreeToImage({
  required TreeSkeleton tree,
  required SpeciesForm form,
  required FoliageState state,
  required int width,
  required int height,
  double timeSeconds = 0,
  Color background = const Color(0xFFE8E6DE),
  bool drawGround = true,
  Bounds? frameTo,
  CanopyAtlas? atlas,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final size = Size(width.toDouble(), height.toDouble());

  canvas.drawRect(Offset.zero & size, Paint()..color = background);

  final groundY = height * 0.86;
  if (drawGround) {
    const GroundRenderer().paint(
      canvas,
      Rect.fromLTRB(0, groundY, size.width, size.height),
      state: state,
      timeSeconds: timeSeconds,
    );
  }

  // Fit to `frameTo` when given, so a row of trees shares one scale.
  //
  // Auto-fitting each cell independently makes a larger tree render smaller,
  // which reads as the tree shrinking as it grows — the opposite of the thing
  // the sheet exists to show.
  final b = (frameTo ?? tree.bounds).inflated(12);
  final scale = math.min(
    size.width / math.max(b.width, 1),
    (groundY - 12) / math.max(b.height, 1),
  );
  canvas.save();
  canvas.translate(size.width / 2, groundY);
  canvas.scale(scale);
  canvas.translate(-(b.minX + b.width / 2), 0);

  TreeRenderer(
    atlas: atlas,
  ).paint(canvas, tree, form: form, state: state, timeSeconds: timeSeconds);
  canvas.restore();

  return recorder.endRecording().toImage(width, height);
}
