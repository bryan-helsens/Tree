import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:grow_domain/grow_domain.dart';
import 'package:grow_flora/grow_flora.dart';
import 'package:grow_render/grow_render.dart';

import 'lab_state.dart';

/// The live preview. Drives its own ticker so wind is visible while tuning —
/// a still tree hides most of what these parameters actually control.
class LabStage extends StatefulWidget {
  const LabStage({required this.state, super.key});

  final LabState state;

  @override
  State<LabStage> createState() => _LabStageState();
}

class _LabStageState extends State<LabStage>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final dt = (elapsed - _last).inMicroseconds / 1e6;
      _last = elapsed;
      if (dt > 0 && dt < 0.5) widget.state.tick(dt);
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFFE8E6DE),
    child: Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(painter: _StagePainter(widget.state)),
        ),
        Positioned(
          left: 16,
          top: 12,
          child: Text(
            widget.state.stats,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF6B7370),
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    ),
  );
}

class _StagePainter extends CustomPainter {
  _StagePainter(this.state) : super(repaint: state);

  final LabState state;

  @override
  void paint(Canvas canvas, Size size) {
    final tree = state.skeleton;

    if (state.showSkeleton) {
      _paintSkeleton(canvas, size, tree);
      return;
    }

    if (state.showWorld) {
      // The same scene the game draws, so tuning happens against the real
      // thing: real sky, real light, real weather, real ground.
      ForestScene(atlas: state.atlas).paint(
        canvas,
        size,
        trees: [
          TreePlacement(
            id: const TreeId('lab'),
            groundX: 0.5,
            depth: 0,
            skeleton: tree,
            form: state.form,
            foliage: state.foliage,
            seed: state.seed,
          ),
        ],
        conditions: state.conditions,
        timeOfDay01: state.timeOfDay,
        timeSeconds: state.time,
        worldSeed: state.seed,
        windAmplitude: state.windAmplitude,
      );
      return;
    }

    _paintBare(canvas, size, tree);
  }

  void _paintBare(Canvas canvas, Size size, TreeSkeleton tree) {
    final groundY = size.height * 0.84;
    const GroundRenderer().paint(
      canvas,
      Rect.fromLTRB(0, groundY, size.width, size.height),
      state: state.foliage,
      timeSeconds: state.time,
    );
    _withTreeTransform(canvas, size, tree, groundY, () {
      TreeRenderer(
        wind: WindField(amplitude: state.windAmplitude),
        atlas: state.atlas,
      ).paint(
        canvas,
        tree,
        form: state.form,
        state: state.foliage,
        timeSeconds: state.time,
      );
    });
  }

  void _paintSkeleton(Canvas canvas, Size size, TreeSkeleton tree) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFE8E6DE),
    );
    final groundY = size.height * 0.84;
    _withTreeTransform(canvas, size, tree, groundY, () {
      final wire = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFF8C3A2E);
      for (final branch in tree.branches) {
        final path = Path()..moveTo(branch.spine.first.x, branch.spine.first.y);
        for (final p in branch.spine.skip(1)) {
          path.lineTo(p.x, p.y);
        }
        canvas.drawPath(path, wire);
      }
    });
  }

  void _withTreeTransform(
    Canvas canvas,
    Size size,
    TreeSkeleton tree,
    double groundY,
    void Function() body,
  ) {
    final b = tree.bounds.inflated(16);
    final scale = (groundY - 24) / (b.height <= 0 ? 1 : b.height);
    canvas.save();
    canvas.translate(size.width / 2, groundY);
    canvas.scale(scale);
    canvas.translate(-(b.minX + b.width / 2), 0);
    body();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StagePainter old) => true;
}
