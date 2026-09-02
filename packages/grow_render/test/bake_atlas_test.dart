import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:grow_render/grow_render.dart';

/// Bakes the placeholder canopy atlases into assets/.
///
///   flutter test test/bake_atlas_test.dart
///
/// These are placeholders. docs/18 specifies what an artist replaces them
/// with; the runtime contract (luminance tiles, square, tinted at draw time)
/// stays the same either way.
void main() {
  testWidgets('bake canopy atlases', (tester) async {
    Directory('assets').createSync(recursive: true);

    // Oak only for now: the brief is one production-quality species before
    // any others. Birch's entry is kept here so adding it later is a one-line
    // change, not a rediscovery of the pipeline.
    const specs = <({String name, int seed, double aspect, int leaves})>[
      (name: 'canopy_oak', seed: 11, aspect: 1.45, leaves: 640),
      // (name: 'canopy_birch', seed: 29, aspect: 1.15, leaves: 520),
    ];

    for (final spec in specs) {
      final baker = CanopyAtlasBaker(leavesPerTile: spec.leaves);
      final atlas = await baker.bake(seed: spec.seed, leafAspect: spec.aspect);
      final data = await atlas.image.toByteData(format: ui.ImageByteFormat.png);
      File(
        'assets/${spec.name}.png',
      ).writeAsBytesSync(data!.buffer.asUint8List());
      atlas.dispose();
    }

    expect(File('assets/canopy_oak.png').existsSync(), isTrue);
  });
}
