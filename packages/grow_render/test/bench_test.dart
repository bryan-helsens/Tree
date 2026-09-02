import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_flora/grow_flora.dart';
import 'package:grow_render/grow_render.dart';

// ignore_for_file: avoid_print

/// Prices the render path, batched against unbatched.
///
/// `record` is the number that matters: it is the per-frame work of building
/// the draw for one tree.
void main() {
  testWidgets('render cost per tree', (tester) async {
    await tester.runAsync(() async {
      final tree = const TreeGenerator().generate(
        rules: oakForm.rules,
        seed: 4242,
        growth01: 1.0,
      );
      print(
        'tree: ${tree.branches.length} branches, '
        '${tree.clusters.length} clusters, ${tree.leafCount} leaves',
      );

      final atlas = await CanopyAtlas.decode(
        File('assets/canopy_oak.png').readAsBytesSync(),
      );

      double measure(TreeRenderer renderer) {
        for (var i = 0; i < 3; i++) {
          final r = ui.PictureRecorder();
          renderer.paint(
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
          renderer.paint(
            Canvas(r),
            tree,
            form: oakForm,
            state: const FoliageState(),
            timeSeconds: i * 0.016,
          );
          r.endRecording().dispose();
        }
        sw.stop();
        return sw.elapsedMicroseconds / runs / 1000;
      }

      for (final q in RenderQuality.values) {
        final unbatched = measure(TreeRenderer(quality: q));
        final batched = measure(TreeRenderer(quality: q, atlas: atlas));
        print(
          '${q.name.padRight(7)} '
          'unbatched ${unbatched.toStringAsFixed(2)} ms  '
          'batched ${batched.toStringAsFixed(2)} ms  '
          '(${(unbatched / batched).toStringAsFixed(1)}x)',
        );
      }
      atlas.dispose();
    });
  });
}
