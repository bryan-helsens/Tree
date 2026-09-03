import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:grow_domain/grow_domain.dart';

/// The colour of the world at a given hour and weather.
///
/// One object owns every environmental colour, so the sky, the light on the
/// canopy, the soil and the atmospheric haze can never drift out of agreement
/// with each other. Time of day is a continuous parameter — there are no
/// discrete "night mode" and "day mode" palettes to keep in sync.
class SkyPalette {
  const SkyPalette({
    required this.zenith,
    required this.horizon,
    required this.sunColour,
    required this.sunHeight,
    required this.ambient,
    required this.haze,
    required this.groundTint,
    required this.isNight,
  });

  final Color zenith;
  final Color horizon;
  final Color sunColour;

  /// 0 at the horizon, 1 overhead. Drives shadow length and light warmth.
  final double sunHeight;

  /// Multiplies everything lit. Night is dim, not merely blue.
  final double ambient;

  /// Distance fade, for aerial perspective on far layers.
  final Color haze;

  final Color groundTint;
  final bool isNight;

  static SkyPalette forConditions(
    WorldConditions conditions,
    double timeOfDay01,
  ) {
    // Sun height: zero at 6am and 6pm, peaking at midday, negative at night.
    final solar = math.sin((timeOfDay01 - 0.25) * 2 * math.pi);
    final height = solar.clamp(-1.0, 1.0).toDouble();
    final day = height.clamp(0.0, 1.0).toDouble();
    final night = height < 0;

    // Dawn and dusk are the interesting moments: warm, low, long-shadowed.
    final goldenness = (1.0 - (height.abs() * 2.2)).clamp(0.0, 1.0).toDouble();

    final overcast = 1.0 - conditions.weather.light;

    Color mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

    // Deep blue at altitude, warmer toward the horizon, grey under cloud.
    var zenith = mix(
      const Color(0xFF16233A), // night
      const Color(0xFF7FA8CB), // clear day
      day,
    );
    var horizon = mix(const Color(0xFF232C3D), const Color(0xFFCBD9DE), day);
    horizon = mix(horizon, const Color(0xFFE0A96D), goldenness * 0.75);
    zenith = mix(zenith, const Color(0xFF8C7A86), goldenness * 0.35);

    zenith = mix(zenith, const Color(0xFF6E7378), overcast * 0.7);
    horizon = mix(horizon, const Color(0xFF9AA0A2), overcast * 0.6);

    final sun = night
        ? const Color(0xFFDCE4F0)
        : mix(const Color(0xFFFFF3D4), const Color(0xFFFFC076), goldenness);

    final ambient =
        (night ? 0.30 : 0.55 + 0.45 * day) * (1.0 - overcast * 0.35);

    return SkyPalette(
      zenith: zenith,
      horizon: horizon,
      sunColour: sun,
      sunHeight: day,
      ambient: ambient.clamp(0.22, 1.0).toDouble(),
      haze: mix(
        horizon,
        const Color(0xFFFFFFFF),
        0.25,
      ).withValues(alpha: 0.55 + overcast * 0.25),
      groundTint: night
          ? const Color(0xFF2C3440)
          : mix(
              const Color(0xFFFFFFFF),
              const Color(0xFFFFD9A8),
              goldenness * 0.6,
            ),
      isNight: night,
    );
  }
}

/// Sky, sun, clouds and the far treeline.
class SkyRenderer {
  const SkyRenderer();

  void paint(
    Canvas canvas,
    Size size, {
    required SkyPalette sky,
    required WorldConditions conditions,
    required double timeOfDay01,
    required double timeSeconds,
    required int worldSeed,
  }) {
    final horizonY = size.height * 0.62;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, horizonY + 2),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(size.width / 2, 0),
          Offset(size.width / 2, horizonY),
          [sky.zenith, sky.horizon],
        ),
    );

    if (sky.isNight) {
      _stars(canvas, size, horizonY, worldSeed, timeSeconds);
    }
    _sunOrMoon(canvas, size, horizonY, sky, timeOfDay01);
    _clouds(canvas, size, horizonY, sky, conditions, timeSeconds, worldSeed);
    _treeline(canvas, size, horizonY, sky);
  }

  void _sunOrMoon(
    Canvas canvas,
    Size size,
    double horizonY,
    SkyPalette sky,
    double tod,
  ) {
    // Below the horizon for part of the night: it should set, not blink out.
    final solar = math.sin((tod - 0.25) * 2 * math.pi);
    final x =
        size.width * (0.12 + 0.76 * ((tod - 0.20) / 0.6).clamp(-0.2, 1.2));
    final y = horizonY - (horizonY * 0.80) * solar;
    if (y > horizonY + 60) return;

    final r = sky.isNight ? 13.0 : 20.0;
    // Glow first, then the disc: a hard disc on a gradient looks pasted on.
    canvas.drawCircle(
      Offset(x, y),
      r * 4.5,
      Paint()
        ..shader = ui.Gradient.radial(Offset(x, y), r * 4.5, [
          sky.sunColour.withValues(alpha: 0.34),
          sky.sunColour.withValues(alpha: 0),
        ]),
    );
    canvas.drawCircle(
      Offset(x, y),
      r,
      Paint()
        ..color = sky.sunColour
        ..isAntiAlias = true,
    );
  }

  void _stars(Canvas canvas, Size size, double horizonY, int seed, double t) {
    final paint = Paint()..isAntiAlias = true;
    for (var i = 0; i < 90; i++) {
      final h = _hash(seed ^ (i * 2654435761));
      final x = (h & 0xFFFF) / 0xFFFF * size.width;
      final y = ((h >> 16) & 0xFFFF) / 0xFFFF * horizonY * 0.92;
      // Slow, shallow twinkle: enough to feel alive, not enough to distract.
      final twinkle = 0.55 + 0.45 * math.sin(t * 0.6 + i * 1.7);
      paint.color = const Color(0xFFFFFFFF).withValues(alpha: 0.55 * twinkle);
      canvas.drawCircle(Offset(x, y), (i % 5 == 0) ? 1.5 : 0.9, paint);
    }
  }

  void _clouds(
    Canvas canvas,
    Size size,
    double horizonY,
    SkyPalette sky,
    WorldConditions conditions,
    double t,
    int seed,
  ) {
    final cover = switch (conditions.weather) {
      WeatherKind.sunny => 3,
      WeatherKind.cloudy => 9,
      WeatherKind.fog => 7,
      _ => 11,
    };
    if (cover == 0) return;

    final tint = Color.lerp(
      const Color(0xFFFFFFFF),
      const Color(0xFF5A6068),
      conditions.weather.isWet ? 0.55 : 0.12,
    )!;

    for (var i = 0; i < cover; i++) {
      final h = _hash(seed ^ (i * 40503));
      // Small and high. Large soft lobes read as fog banks rather than as
      // clouds, and they swallow the frame.
      final baseY = horizonY * (0.08 + ((h >> 8) & 0xFF) / 255 * 0.34);
      final scale = 0.28 + ((h >> 16) & 0xFF) / 255 * 0.42;
      // Clouds drift on the same wind that moves the canopy.
      final drift =
          (t * (5 + (h & 7)) + (h & 0xFFFF) % size.width) % (size.width + 320);
      final x = drift - 160;
      _cloud(
        canvas,
        Offset(x, baseY),
        scale,
        tint.withValues(alpha: 0.85),
        sky.ambient,
      );
    }
  }

  void _cloud(
    Canvas canvas,
    Offset at,
    double scale,
    Color colour,
    double ambient,
  ) {
    final paint = Paint()
      ..color = Color.lerp(
        colour,
        const Color(0xFF000000),
        (1 - ambient) * 0.35,
      )!
      ..isAntiAlias = true
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    for (final lobe in const [
      (dx: 0.0, dy: 0.0, r: 34.0),
      (dx: 30.0, dy: 6.0, r: 26.0),
      (dx: -28.0, dy: 8.0, r: 22.0),
      (dx: 12.0, dy: -12.0, r: 24.0),
    ]) {
      canvas.drawCircle(
        at + Offset(lobe.dx * scale, lobe.dy * scale),
        lobe.r * scale,
        paint,
      );
    }
  }

  /// A distant treeline, desaturated toward the haze.
  ///
  /// Depth here comes from atmospheric perspective rather than from drop
  /// shadows: far things go pale and low-contrast, which is what makes the
  /// near tree feel near.
  void _treeline(Canvas canvas, Size size, double horizonY, SkyPalette sky) {
    for (final layer in const [
      (offset: 0.0, height: 46.0, fade: 0.80),
      (offset: 14.0, height: 62.0, fade: 0.58),
    ]) {
      final path = Path()..moveTo(0, horizonY + layer.offset);
      var x = 0.0;
      var i = 0;
      while (x < size.width + 40) {
        final w = 26.0 + (i % 5) * 9;
        final h = layer.height * (0.62 + ((i * 37) % 100) / 100 * 0.55);
        path
          ..lineTo(x + w * 0.25, horizonY + layer.offset - h * 0.75)
          ..lineTo(x + w * 0.5, horizonY + layer.offset - h)
          ..lineTo(x + w * 0.78, horizonY + layer.offset - h * 0.7)
          ..lineTo(x + w, horizonY + layer.offset - h * 0.15);
        x += w;
        i++;
      }
      path
        ..lineTo(size.width, horizonY + 90)
        ..lineTo(0, horizonY + 90)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color = Color.lerp(const Color(0xFF3F5340), sky.haze, layer.fade)!
          ..isAntiAlias = true,
      );
    }
  }
}

int _hash(int x) {
  var h = x & 0xFFFFFFFF;
  h ^= h >>> 15;
  h = (h * 0x85EBCA6B) & 0xFFFFFFFF;
  h ^= h >>> 13;
  return h & 0xFFFFFFFF;
}
