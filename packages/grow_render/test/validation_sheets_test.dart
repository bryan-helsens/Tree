import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_domain/grow_domain.dart';
import 'package:grow_flora/grow_flora.dart';
import 'package:grow_render/grow_render.dart';

/// Validation sheets for the first production-quality species.
///
/// Run one at a time; each writes into build/art_review/.
///   flutter test test/validation_sheets_test.dart --plain-name "growth ladder"
void main() {
  const out = 'build/art_review';
  late CanopyAtlas atlas;

  Future<void> withAtlas(WidgetTester tester, Future<void> Function() body) =>
      tester
          .runAsync(() async {
            Directory(out).createSync(recursive: true);
            await _loadFont();
            atlas = await CanopyAtlas.decode(
              File('assets/canopy_oak.png').readAsBytesSync(),
            );
            await body();
            atlas.dispose();
          })
          .then((_) {});

  Future<void> write(String name, ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$out/$name').writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  }

  testWidgets(
    'growth ladder',
    (t) => withAtlas(t, () async {
      await write(
        'v_growth_ladder.png',
        await _sheet(
          atlas: atlas,
          label: 'Pedunculate Oak — growth, shared scale',
          count: 8,
          build: (i) {
            final g = 0.08 + (i / 7) * 0.92;
            return (
              growth: g,
              seed: 4242,
              state: const FoliageState(),
              caption: '${(g * 100).round()}%',
            );
          },
        ),
      );
    }),
  );

  testWidgets(
    'growth animation continuity',
    (t) => withAtlas(t, () async {
      // Closely spaced steps: if growth is continuous these read as one
      // tree easing outward, with nothing appearing or jumping.
      await write(
        'v_growth_continuity.png',
        await _sheet(
          atlas: atlas,
          label: 'Growth continuity — 2% steps around a branch emergence',
          count: 8,
          build: (i) {
            final g = 0.42 + i * 0.02;
            return (
              growth: g,
              seed: 4242,
              state: const FoliageState(),
              caption: '${(g * 100).toStringAsFixed(0)}%',
            );
          },
        ),
      );
    }),
  );

  testWidgets(
    'health states',
    (t) => withAtlas(t, () async {
      const states = <(String, FoliageState)>[
        ('thriving', FoliageState(sparkle: 1.0)),
        ('thirsty', FoliageState(droop: 0.8)),
        ('overwatered', FoliageState(wetness: 0.9, droop: 0.35)),
        ('starved', FoliageState(pallor: 0.85)),
        ('overfed', FoliageState(scorch: 0.8)),
        ('flowering', FoliageState(flowering: 0.9, sparkle: 0.4)),
        ('ailing', FoliageState(pallor: 0.5, droop: 0.6, bareness: 0.35)),
        ('recovering', FoliageState(pallor: 0.2, droop: 0.15)),
      ];
      await write(
        'v_health_states.png',
        await _sheet(
          atlas: atlas,
          label: 'Condition — every state is simulation-driven, not drawn',
          count: states.length,
          build: (i) => (
            growth: 0.9,
            seed: 4242,
            state: states[i].$2,
            caption: states[i].$1,
          ),
        ),
      );
    }),
  );

  testWidgets(
    'individual variation',
    (t) => withAtlas(t, () async {
      await write(
        'v_individuals.png',
        await _sheet(
          atlas: atlas,
          label: 'Eight individuals — one species, one parameter set',
          count: 8,
          build: (i) => (
            growth: 0.9,
            seed: 1000 + i * 7919,
            state: const FoliageState(),
            caption: 'seed ${1000 + i * 7919}',
          ),
        ),
      );
    }),
  );

  testWidgets(
    'wind movement',
    (t) => withAtlas(t, () async {
      await write(
        'v_wind.png',
        await _sheet(
          atlas: atlas,
          label: 'Wind — the same tree across one gust, 0.4s apart',
          count: 8,
          build: (i) => (
            growth: 0.9,
            seed: 4242,
            state: const FoliageState(),
            caption: '${(i * 0.4).toStringAsFixed(1)}s',
          ),
          timeOf: (i) => i * 0.4,
        ),
      );
    }),
  );
}

typedef _Spec = ({double growth, int seed, FoliageState state, String caption});

Future<ui.Image> _sheet({
  required CanopyAtlas atlas,
  required String label,
  required int count,
  required _Spec Function(int) build,
  double Function(int)? timeOf,
  int cellWidth = 250,
  int cellHeight = 340,
}) async {
  const header = 44;
  final specs = [for (var i = 0; i < count; i++) build(i)];
  final trees = [
    for (final s in specs)
      const TreeGenerator().generate(
        rules: oakForm.rules,
        seed: s.seed,
        growth01: s.growth,
      ),
  ];
  // One shared frame so a bigger tree renders bigger.
  final frame = Bounds.around([
    for (final t in trees) ...[
      Vec2(t.bounds.minX, t.bounds.minY),
      Vec2(t.bounds.maxX, t.bounds.maxY),
    ],
  ]);

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final width = count * cellWidth;
  final height = cellHeight + header;
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFFF4F5F3),
  );
  _text(canvas, label, const Offset(16, 12), 19, const Color(0xFF191E1B));

  final pending = <ui.Image>[];
  for (var i = 0; i < count; i++) {
    final img = await renderTreeToImage(
      tree: trees[i],
      form: oakForm,
      state: specs[i].state,
      width: cellWidth,
      height: cellHeight,
      frameTo: frame,
      atlas: atlas,
      timeSeconds: timeOf?.call(i) ?? 0,
    );
    canvas.drawImage(
      img,
      Offset(i * cellWidth.toDouble(), header.toDouble()),
      Paint(),
    );
    pending.add(img);
    _text(
      canvas,
      specs[i].caption,
      Offset(i * cellWidth + 12.0, header + cellHeight - 26.0),
      15,
      const Color(0xFF414945),
    );
  }

  final sheet = await recorder.endRecording().toImage(width, height);
  // Disposed only after the picture referencing them has been rasterised.
  for (final p in pending) {
    p.dispose();
  }
  return sheet;
}

Future<void> _loadFont() async {
  for (final path in const [
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/System/Library/Fonts/Helvetica.ttc',
  ]) {
    final f = File(path);
    if (f.existsSync()) {
      await ui.loadFontFromList(f.readAsBytesSync(), fontFamily: 'ReviewSans');
      return;
    }
  }
}

void _text(Canvas c, String s, Offset at, double size, Color colour) {
  final tp = TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(color: colour, fontSize: size, fontFamily: 'ReviewSans'),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, at);
}
