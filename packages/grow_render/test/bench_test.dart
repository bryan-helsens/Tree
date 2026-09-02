import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_flora/grow_flora.dart';
import 'package:grow_render/grow_render.dart';

// ignore_for_file: avoid_print

/// Costs the render path at each quality tier.
///
/// The number that matters is `record` — building the paths — because that is
/// what would run per frame today. Moving leaves onto a batched atlas draw is
/// the Week 3 optimisation; this measures how much it is needed.
void main() {
  testWidgets('render cost per tree', (tester) async {
    final tree = const TreeGenerator().generate(
      rules: oakForm.rules,
      seed: 4242,
      growth01: 1.0,
    );
    print(
      'tree: ${tree.branches.length} branches, ${tree.leafCount} leaves, '
      '${tree.segmentCount} segments',
    );

    for (final q in RenderQuality.values) {
      // Warm up, then measure.
      for (var i = 0; i < 3; i++) {
        final r = ui.PictureRecorder();
        TreeRenderer(quality: q).paint(
          Canvas(r),
          tree,
          form: oakForm,
          state: const FoliageState(),
          timeSeconds: 0,
        );
        r.endRecording().dispose();
      }
      const runs = 20;
      final sw = Stopwatch()..start();
      for (var i = 0; i < runs; i++) {
        final r = ui.PictureRecorder();
        TreeRenderer(quality: q).paint(
          Canvas(r),
          tree,
          form: oakForm,
          state: const FoliageState(),
          timeSeconds: i * 0.016,
        );
        r.endRecording().dispose();
      }
      sw.stop();
      print(
        '${q.name.padRight(7)} cap ${q.leafCap.toString().padLeft(4)}  '
        '${(sw.elapsedMicroseconds / runs / 1000).toStringAsFixed(2)} ms/tree',
      );
    }
  });
}
