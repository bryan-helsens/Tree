import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:grow_flora/grow_flora.dart';
import 'package:grow_render/grow_render.dart';

/// The hybrid Oak at the size a player judges it.
void main() {
  testWidgets('hybrid hero oak', (tester) async {
    // Image decoding goes through the engine and needs real async: inside
    // testWidgets' fake-async zone the codec future never completes.
    await tester.runAsync(() async {
      Directory('build/art_review').createSync(recursive: true);
      final atlas = await CanopyAtlas.decode(
        File('assets/canopy_oak.png').readAsBytesSync(),
      );

      final image = await renderTreeToImage(
        tree: const TreeGenerator().generate(
          rules: oakForm.rules,
          seed: 4242,
          growth01: 0.95,
        ),
        form: oakForm,
        state: const FoliageState(sparkle: 0.8),
        width: 760,
        height: 820,
        atlas: atlas,
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      File(
        'build/art_review/hybrid_hero.png',
      ).writeAsBytesSync(data!.buffer.asUint8List());
      image.dispose();
      atlas.dispose();
    });
  });
}
