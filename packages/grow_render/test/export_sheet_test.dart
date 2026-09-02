import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_flora/grow_flora.dart';
import 'package:grow_render/grow_render.dart';

/// Renders review sheets through the real Canvas pipeline.
///
/// Not a golden test — it produces the images a human looks at for the week-2
/// art review. Judging procedural output from a description is how you end up
/// shipping something nobody wants to look at.
///
///   flutter test test/export_sheet_test.dart
///
/// Output lands in build/art_review/.
void main() {
  const outDir = 'build/art_review';

  setUpAll(() async {
    Directory(outDir).createSync(recursive: true);
    // flutter_test ships the Ahem placeholder font, which draws every glyph as
    // a filled box. Load a real face so the review sheets can be read.
    for (final path in const [
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
      '/System/Library/Fonts/Helvetica.ttc',
    ]) {
      final f = File(path);
      if (f.existsSync()) {
        await ui.loadFontFromList(
          f.readAsBytesSync(),
          fontFamily: 'ReviewSans',
        );
        break;
      }
    }
  });

  Future<void> write(String name, ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$outDir/$name').writeAsBytesSync(data!.buffer.asUint8List());
    // ui.Image holds native memory the GC does not account for. Leaking these
    // across a multi-sheet run is what was killing the process.
    image.dispose();
  }

  testWidgets('growth stages, both species', (tester) async {
    for (final form in [oakForm, birchForm]) {
      final image = await _sheet(
        columns: 6,
        cellWidth: 250,
        cellHeight: 360,
        label: form.id,
        build: (i) {
          // Stage 1 through 6 of the ladder the player actually climbs.
          final growth = (i + 1) / 6.0;
          return (
            tree: const TreeGenerator().generate(
              rules: form.rules,
              seed: 4242,
              growth01: growth,
            ),
            form: form,
            state: const FoliageState(sparkle: 0.6),
            caption: 'growth ${(growth * 100).round()}%',
          );
        },
      );
      await write('stages_${form.id}.png', image);
    }
  });

  testWidgets('health states on a mature oak', (tester) async {
    const states = <(String, FoliageState)>[
      ('thriving', FoliageState(sparkle: 1.0)),
      ('thirsty', FoliageState(droop: 0.75)),
      ('overwatered', FoliageState(wetness: 0.9, droop: 0.35)),
      ('starved', FoliageState(pallor: 0.85)),
      ('overfed', FoliageState(scorch: 0.8)),
      ('flowering', FoliageState(flowering: 0.9, sparkle: 0.4)),
    ];
    final image = await _sheet(
      columns: 6,
      cellWidth: 300,
      cellHeight: 380,
      label: 'oak health',
      build: (i) => (
        tree: const TreeGenerator().generate(
          rules: oakForm.rules,
          seed: 4242,
          growth01: 0.82,
        ),
        form: oakForm,
        state: states[i].$2,
        caption: states[i].$1,
      ),
    );
    await write('health_oak.png', image);
  });

  testWidgets('individual variation — same species, different seeds', (
    tester,
  ) async {
    for (final form in [oakForm, birchForm]) {
      final image = await _sheet(
        columns: 6,
        cellWidth: 250,
        cellHeight: 360,
        label: '${form.id} — six individuals',
        build: (i) => (
          tree: const TreeGenerator().generate(
            rules: form.rules,
            seed: 1000 + i * 7919,
            growth01: 0.85,
          ),
          form: form,
          state: const FoliageState(),
          caption: 'seed ${1000 + i * 7919}',
        ),
      );
      await write('variation_${form.id}.png', image);
    }
  });

  testWidgets('hero — one mature oak, large', (tester) async {
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
    );
    await write('hero_oak.png', image);
  });
}

typedef _Cell = ({
  TreeSkeleton tree,
  SpeciesForm form,
  FoliageState state,
  String caption,
});

/// Lays cells out in a row with captions, so a reviewer can compare.
Future<ui.Image> _sheet({
  required int columns,
  required int cellWidth,
  required int cellHeight,
  required String label,
  required _Cell Function(int) build,
  bool sharedScale = true,
}) async {
  const headerHeight = 46;
  final width = columns * cellWidth;
  final height = cellHeight + headerHeight;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final pending = <ui.Image>[];
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFFF4F5F3),
  );

  _text(canvas, label, const Offset(16, 12), 20, const Color(0xFF191E1B));

  // One shared frame across the row, sized to the largest specimen.
  final cells = [for (var i = 0; i < columns; i++) build(i)];
  final frame = Bounds.around([
    for (final c in cells) ...[
      Vec2(c.tree.bounds.minX, c.tree.bounds.minY),
      Vec2(c.tree.bounds.maxX, c.tree.bounds.maxY),
    ],
  ]);

  for (var i = 0; i < columns; i++) {
    final cell = cells[i];
    final image = await renderTreeToImage(
      tree: cell.tree,
      form: cell.form,
      state: cell.state,
      width: cellWidth,
      height: cellHeight,
      frameTo: sharedScale ? frame : null,
    );
    canvas.drawImage(
      image,
      Offset(i * cellWidth.toDouble(), headerHeight.toDouble()),
      Paint(),
    );
    // Held until the sheet is rasterised: the Picture still references these,
    // and disposing early is a use-after-free on native memory.
    pending.add(image);
    _text(
      canvas,
      cell.caption,
      Offset(i * cellWidth.toDouble() + 12, headerHeight + cellHeight - 26.0),
      15,
      const Color(0xFF414945),
    );
  }

  final sheet = await recorder.endRecording().toImage(width, height);
  for (final img in pending) {
    img.dispose();
  }
  return sheet;
}

void _text(Canvas canvas, String s, Offset at, double size, Color colour) {
  final tp = TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(color: colour, fontSize: size, fontFamily: 'ReviewSans'),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, at);
}
