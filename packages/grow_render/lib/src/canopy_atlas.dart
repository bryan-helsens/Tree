import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// The canopy sprite atlas: a grid of leaf-mass tiles drawn once and blitted
/// many times.
///
/// Tiles are **luminance only** — white where foliage is brightest, dark where
/// it is shadowed, transparent between leaves. Colour comes entirely from the
/// runtime tint, which is what keeps every health state, season and species a
/// palette change rather than a new drawing.
class CanopyAtlas {
  const CanopyAtlas({
    required this.image,
    required this.tileSize,
    required this.columns,
    required this.rows,
  });

  final ui.Image image;
  final int tileSize;
  final int columns;
  final int rows;

  int get tileCount => columns * rows;

  Rect tileRect(int index) {
    final i = index % tileCount;
    final x = (i % columns) * tileSize;
    final y = (i ~/ columns) * tileSize;
    return Rect.fromLTWH(
      x.toDouble(),
      y.toDouble(),
      tileSize.toDouble(),
      tileSize.toDouble(),
    );
  }

  void dispose() => image.dispose();

  /// Loads a baked atlas from encoded PNG bytes.
  ///
  /// The app loads these from its asset bundle; tools and tests load them from
  /// disk. Either way the tile grid has to match how the atlas was baked.
  static Future<CanopyAtlas> decode(
    Uint8List bytes, {
    int tileSize = 256,
    int columns = 3,
    int rows = 2,
  }) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return CanopyAtlas(
      image: frame.image,
      tileSize: tileSize,
      columns: columns,
      rows: rows,
    );
  }
}

/// Bakes a canopy atlas.
///
/// **These are placeholders.** They exist so the hybrid pipeline is real and
/// measurable end to end; the spec in docs/18 describes what a 2D artist
/// replaces them with. Baking offline buys density and layering that would be
/// far too expensive per frame — several hundred leaf shapes per tile against
/// a runtime budget of a few dozen draws for a whole tree.
class CanopyAtlasBaker {
  const CanopyAtlasBaker({
    this.tileSize = 256,
    this.columns = 3,
    this.rows = 2,
    this.leavesPerTile = 620,
  });

  final int tileSize;
  final int columns;
  final int rows;
  final int leavesPerTile;

  Future<CanopyAtlas> bake({
    required int seed,
    required double leafAspect,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    for (var tile = 0; tile < columns * rows; tile++) {
      canvas.save();
      canvas.translate(
        (tile % columns) * tileSize.toDouble(),
        (tile ~/ columns) * tileSize.toDouble(),
      );
      canvas.clipRect(
        Rect.fromLTWH(0, 0, tileSize.toDouble(), tileSize.toDouble()),
      );
      _bakeTile(canvas, seed * 977 + tile * 31, leafAspect);
      canvas.restore();
    }

    final image = await recorder.endRecording().toImage(
      columns * tileSize,
      rows * tileSize,
    );
    return CanopyAtlas(
      image: image,
      tileSize: tileSize,
      columns: columns,
      rows: rows,
    );
  }

  void _bakeTile(Canvas canvas, int seed, double leafAspect) {
    final rng = _Rng(seed);
    final centre = Offset(tileSize / 2, tileSize / 2);
    final radius = tileSize * 0.40;

    // An irregular envelope built from a few overlapping lobes. A circular
    // mass reads as a bush; real canopy clumps are lopsided.
    final lobes = <({Offset centre, double radius})>[];
    final lobeCount = 3 + rng.nextInt(3);
    for (var i = 0; i < lobeCount; i++) {
      final a = rng.range(0, math.pi * 2);
      final d = rng.range(0, radius * 0.42);
      lobes.add((
        centre: centre + Offset(math.cos(a) * d, math.sin(a) * d * 0.85),
        radius: radius * rng.range(0.55, 0.92),
      ));
    }

    double envelope(Offset p) {
      // Distance to the nearest lobe surface, normalised: 1 deep inside,
      // 0 at the edge, negative outside.
      var best = -1e9;
      for (final l in lobes) {
        final v = 1.0 - (p - l.centre).distance / l.radius;
        if (v > best) best = v;
      }
      return best;
    }

    // Light from upper-left, consistent across every tile so a canopy built
    // from several of them still reads as one lit object.
    const lightDir = Offset(-0.55, -0.83);

    var placed = 0;
    var attempts = 0;
    while (placed < leavesPerTile && attempts < leavesPerTile * 12) {
      attempts++;
      final p = Offset(rng.range(6, tileSize - 6), rng.range(6, tileSize - 6));
      final e = envelope(p);
      // Leaves thin out toward the edge and a few break past it, which is
      // what gives the silhouette a leafy rather than a cut-out edge.
      if (e < -0.06) continue;
      final edgeKeep = e < 0 ? 0.22 : math.min(1.0, 0.35 + e * 1.9);
      if (rng.unit() > edgeKeep) continue;

      final toward = p - centre;
      final facing = toward.distance == 0
          ? 0.0
          : (toward.dx * lightDir.dx + toward.dy * lightDir.dy) /
                toward.distance;

      // Self-shading: the interior sits back, the lit face comes forward.
      //
      // Kept deliberately bright and low-contrast. These tiles are multiplied
      // by the leaf tint at draw time, so baking a dark interior darkens it
      // twice and the canopy reads as holes rather than depth. Shading is the
      // sprite's job; being green is the tint's.
      final depth = e.clamp(0.0, 1.0);
      var lum = 0.66 + 0.20 * (1 - depth) + 0.010 * facing * 22;
      lum += rng.range(-0.07, 0.07);
      final l = (lum.clamp(0.40, 1.0) * 255).round();

      final size = tileSize * rng.range(0.030, 0.058);
      _leaf(
        canvas,
        p,
        rng.range(-math.pi, math.pi),
        size,
        leafAspect,
        Color.fromARGB(255, l, l, l),
      );
      placed++;
    }
  }

  void _leaf(
    Canvas canvas,
    Offset at,
    double angle,
    double size,
    double aspect,
    Color colour,
  ) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(angle);
    final w = size, h = size * aspect;
    canvas.drawPath(
      Path()
        ..moveTo(0, -h / 2)
        ..quadraticBezierTo(w * 0.70, -h * 0.05, 0, h / 2)
        ..quadraticBezierTo(-w * 0.70, -h * 0.05, 0, -h / 2)
        ..close(),
      Paint()
        ..color = colour
        ..isAntiAlias = true,
    );
    canvas.restore();
  }
}

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
  int nextInt(int max) => _next() % max;
}
