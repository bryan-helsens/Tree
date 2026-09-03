import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// What kind of care just happened.
enum CareKind { water, feed }

/// A burst of particles over a tree that has just been tended.
///
/// **Triggered by a domain fact, never by a button.** The renderer watches the
/// tree's `timesWatered` / `timesFed` counters — real, persisted, simulated
/// state — and plays a burst when one increments. A tap that fails validation
/// increments nothing and produces nothing, with no special case anywhere.
///
/// The result is that the visual is genuinely a consequence: the tree responds
/// because its state changed, which is exactly the feeling the design is
/// after.
class CareEffect extends StatefulWidget {
  const CareEffect({
    required this.waterCount,
    required this.feedCount,
    required this.size,
    super.key,
  });

  final int waterCount;
  final int feedCount;
  final Size size;

  @override
  State<CareEffect> createState() => _CareEffectState();
}

class _CareEffectState extends State<CareEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  CareKind _kind = CareKind.water;
  late int _water = widget.waterCount;
  late int _feed = widget.feedCount;

  @override
  void didUpdateWidget(CareEffect old) {
    super.didUpdateWidget(old);
    // The counters are the trigger. Nothing else can start this.
    if (widget.waterCount != _water) {
      _water = widget.waterCount;
      _burst(CareKind.water);
    } else if (widget.feedCount != _feed) {
      _feed = widget.feedCount;
      _burst(CareKind.feed);
    }
  }

  void _burst(CareKind kind) {
    _kind = kind;
    _controller
      ..reset()
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          size: widget.size,
          painter: _CarePainter(
            progress: _controller.value,
            kind: _kind,
            reduceMotion: reduceMotion,
          ),
        ),
      ),
    );
  }
}

class _CarePainter extends CustomPainter {
  const _CarePainter({
    required this.progress,
    required this.kind,
    required this.reduceMotion,
  });

  final double progress;
  final CareKind kind;
  final bool reduceMotion;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;

    final count = reduceMotion ? 6 : 18;
    final paint = Paint()..isAntiAlias = true;
    // Water falls from above and darkens the soil; feed scatters at the base.
    final fromTop = kind == CareKind.water;

    for (var i = 0; i < count; i++) {
      final h = _hash(i * 2654435761 + kind.index);
      final spread = ((h & 0xFFFF) / 0xFFFF - 0.5) * size.width * 0.7;
      final delay = ((h >> 16) & 0xFF) / 255 * 0.35;
      final t = ((progress - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (t <= 0) continue;

      final fade = math.sin(t * math.pi).clamp(0.0, 1.0);
      final x = size.width / 2 + spread * (fromTop ? 1 : 0.6);
      final y = fromTop
          // Falls, then lands.
          ? size.height * (0.18 + 0.72 * _accelerate(t))
          : size.height * (0.92 - 0.16 * math.sin(t * math.pi));

      paint.color =
          (fromTop ? const Color(0xFF7FB4CC) : const Color(0xFF9A8B4F))
              .withValues(alpha: fade * (fromTop ? 0.75 : 0.65));

      if (fromTop) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(x, y), width: 2.4, height: 7),
            const Radius.circular(1.4),
          ),
          paint,
        );
      } else {
        canvas.drawCircle(Offset(x, y), 1.9, paint);
      }
    }
  }

  double _accelerate(double t) => t * t;

  @override
  bool shouldRepaint(_CarePainter old) =>
      old.progress != progress || old.kind != kind;
}

int _hash(int x) {
  var h = x & 0xFFFFFFFF;
  h ^= h >>> 15;
  h = (h * 0x85EBCA6B) & 0xFFFFFFFF;
  h ^= h >>> 13;
  return h & 0xFFFFFFFF;
}
