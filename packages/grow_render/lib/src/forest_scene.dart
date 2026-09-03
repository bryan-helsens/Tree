import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:grow_domain/grow_domain.dart';
import 'package:grow_flora/grow_flora.dart';

import 'canopy_atlas.dart';
import 'sky.dart';
import 'tree_painter.dart';

/// Where a tree sits in the world, and how big it reads.
class TreePlacement {
  const TreePlacement({
    required this.id,
    required this.groundX,
    required this.depth,
    required this.skeleton,
    required this.form,
    required this.foliage,
    required this.seed,
  });

  final TreeId id;

  /// 0..1 across the plot.
  final double groundX;

  /// 0 = nearest the camera, 1 = furthest. Drives scale and haze.
  final double depth;

  final TreeSkeleton skeleton;
  final SpeciesForm form;
  final FoliageState foliage;
  final int seed;
}

/// The whole world: sky, light, ground, trees, weather, atmosphere.
///
/// Everything it draws comes from simulation state. There is no separate
/// "weather look" or "night look" to keep in step with the simulation — the
/// sky palette, the light on the canopy and the wetness of the soil are all
/// read from the same conditions the trees are living in.
class ForestScene {
  const ForestScene({this.atlas, this.quality = RenderQuality.high});

  final CanopyAtlas? atlas;
  final RenderQuality quality;

  static const double horizonFraction = 0.62;
  static const double groundFraction = 0.72;

  void paint(
    Canvas canvas,
    Size size, {
    required List<TreePlacement> trees,
    required WorldConditions conditions,
    required double timeOfDay01,
    required double timeSeconds,
    required int worldSeed,
    double windAmplitude = 1.0,
  }) {
    final sky = SkyPalette.forConditions(conditions, timeOfDay01);
    final wind = WindField(
      amplitude:
          windAmplitude * (conditions.weather == WeatherKind.storm ? 3.0 : 1.0),
    );

    const SkyRenderer().paint(
      canvas,
      size,
      sky: sky,
      conditions: conditions,
      timeOfDay01: timeOfDay01,
      timeSeconds: timeSeconds,
      worldSeed: worldSeed,
    );

    _ground(canvas, size, sky, trees, timeSeconds);

    // Far trees first, and hazier, so the plot has depth.
    final ordered = [...trees]..sort((a, b) => b.depth.compareTo(a.depth));
    for (final t in ordered) {
      _tree(
        canvas,
        size,
        t,
        sky,
        wind,
        timeSeconds,
        conditionsFog: conditions.weather == WeatherKind.fog,
      );
    }

    if (conditions.isRaining) {
      _rain(canvas, size, conditions, timeSeconds, worldSeed);
    }
    _atmosphere(canvas, size, sky, conditions);
  }

  // ─── ground ────────────────────────────────────────────────────────────

  void _ground(
    Canvas canvas,
    Size size,
    SkyPalette sky,
    List<TreePlacement> trees,
    double t,
  ) {
    final groundY = size.height * groundFraction;
    final horizonY = size.height * horizonFraction;

    // The strip between horizon and plot: middle distance, hazed.
    canvas.drawRect(
      Rect.fromLTWH(0, horizonY, size.width, groundY - horizonY + 1),
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, horizonY), Offset(0, groundY), [
          Color.lerp(const Color(0xFF6C7F55), sky.haze, 0.45)!,
          const Color(0xFF54703C),
        ]),
    );

    // Wetness is the mean across the plot: it is the soil, not any one tree.
    final wetness = trees.isEmpty
        ? 0.0
        : trees.map((e) => e.foliage.wetness).reduce((a, b) => a + b) /
              trees.length;

    const GroundRenderer().paint(
      canvas,
      Rect.fromLTRB(0, groundY, size.width, size.height),
      state: FoliageState(wetness: wetness),
      timeSeconds: t,
    );

    // Night and golden hour tint the ground as much as the sky.
    canvas.drawRect(
      Rect.fromLTRB(0, horizonY, size.width, size.height),
      Paint()
        ..color = sky.groundTint.withValues(alpha: sky.isNight ? 0.42 : 0.16)
        ..blendMode = sky.isNight ? BlendMode.multiply : BlendMode.overlay,
    );
  }

  // ─── trees ─────────────────────────────────────────────────────────────

  void _tree(
    Canvas canvas,
    Size size,
    TreePlacement placement,
    SkyPalette sky,
    WindField wind,
    double t, {
    bool conditionsFog = false,
  }) {
    final groundY = size.height * groundFraction;
    // Further back sits higher on the plot and reads smaller.
    final baseY =
        groundY + (size.height - groundY) * (1 - placement.depth) * 0.5;
    final scale =
        (1.0 - placement.depth * 0.42) * (size.height / 620).clamp(0.5, 1.6);

    canvas.save();
    canvas.translate(size.width * placement.groundX, baseY);
    canvas.scale(scale);

    _shadow(canvas, placement, sky);

    TreeRenderer(
      wind: wind,
      quality: quality,
      atlas: atlas,
      haze: sky.haze,
      // Distance fade, plus a little extra in fog.
      hazeAmount:
          placement.depth * 0.55 +
          (conditionsFog ? 0.18 : 0.0) +
          (1.0 - sky.ambient) * 0.12,
    ).paint(
      canvas,
      placement.skeleton,
      form: placement.form,
      state: placement.foliage,
      timeSeconds: t,
    );
    canvas.restore();
  }

  /// A soft ellipse under the trunk, lengthening and softening as the sun
  /// drops. Contact shadow is most of what stops a tree looking pasted on.
  void _shadow(Canvas canvas, TreePlacement placement, SkyPalette sky) {
    final spread = placement.skeleton.bounds.width * 0.42 + 8;
    final lengthen = 1.0 + (1.0 - sky.sunHeight) * 1.6;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(spread * 0.10 * lengthen, 2),
        width: spread * 1.5 * lengthen,
        height: spread * 0.34,
      ),
      Paint()
        ..color = const Color(
          0xFF2A2A20,
        ).withValues(alpha: 0.16 + 0.16 * sky.sunHeight)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
  }

  // ─── weather and atmosphere ────────────────────────────────────────────

  void _rain(
    Canvas canvas,
    Size size,
    WorldConditions conditions,
    double t,
    int seed,
  ) {
    // Intensity follows the simulated rate, so heavy rain looks heavy and the
    // drizzle between showers looks like drizzle.
    final intensity = (conditions.rainRate / 6.0).clamp(0.15, 1.0);
    final count = (140 * intensity).round();
    final paint = Paint()
      ..color = const Color(
        0xFFBFD2DC,
      ).withValues(alpha: 0.34 + 0.2 * intensity)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < count; i++) {
      final h = _hash(seed ^ (i * 2654435761));
      final speed = 620 + (h & 0xFF);
      final x = (h % 10007) / 10007 * size.width;
      final y = ((t * speed + (h >> 8) % 1000) % (size.height + 60)) - 30;
      final len = 9.0 + intensity * 12;
      canvas.drawLine(Offset(x, y), Offset(x - 2.5, y + len), paint);
    }
  }

  void _atmosphere(
    Canvas canvas,
    Size size,
    SkyPalette sky,
    WorldConditions conditions,
  ) {
    if (conditions.weather == WeatherKind.fog) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, size.height * horizonFraction),
            Offset(0, size.height),
            [
              sky.haze.withValues(alpha: 0.55),
              sky.haze.withValues(alpha: 0.12),
            ],
          ),
      );
    }

    // A restrained vignette: it settles the eye toward the middle without
    // announcing itself.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width / 2, size.height * 0.52),
          math.max(size.width, size.height) * 0.72,
          [
            const Color(0x00000000),
            Color.lerp(
              const Color(0x00000000),
              const Color(0xFF0B1016),
              sky.isNight ? 0.28 : 0.14,
            )!,
          ],
        ),
    );
  }
}

int _hash(int x) {
  var h = x & 0xFFFFFFFF;
  h ^= h >>> 15;
  h = (h * 0x85EBCA6B) & 0xFFFFFFFF;
  h ^= h >>> 13;
  return h & 0xFFFFFFFF;
}
