import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_content/grow_content.dart';
import 'package:grow_domain/grow_domain.dart';
import 'package:grow_flora/grow_flora.dart';
import 'package:grow_render/grow_render.dart';
import 'package:grow_sim/grow_sim.dart';

/// World scene sheets. Run one at a time:
///   flutter test test/world_sheets_test.dart --plain-name "day cycle"
void main() {
  const out = 'build/art_review';

  Future<void> sheet({
    required WidgetTester tester,
    required String file,
    required String label,
    required int count,
    required ({WorldConditions conditions, double timeOfDay, String caption})
    Function(int)
    build,
  }) => tester.runAsync(() async {
    Directory(out).createSync(recursive: true);
    await _loadFont();
    final atlas = await CanopyAtlas.decode(
      File('assets/canopy_oak.png').readAsBytesSync(),
    );

    const cellW = 330, cellH = 400, header = 44;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final w = (count * cellW).toDouble();
    final h = (cellH + header).toDouble();
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = const Color(0xFFF4F5F3),
    );
    _text(canvas, label, const Offset(16, 12), 19, const Color(0xFF191E1B));

    // Three oaks at different depths and maturities: a plot, not a
    // specimen. Depth is what makes the scene read as a place.
    final placements = <TreePlacement>[
      for (final p in const [
        (x: 0.30, depth: 0.0, g: 0.92, seed: 4242),
        (x: 0.62, depth: 0.35, g: 0.70, seed: 8171),
        (x: 0.84, depth: 0.62, g: 0.48, seed: 3313),
      ])
        TreePlacement(
          id: TreeId('t${p.seed}'),
          groundX: p.x,
          depth: p.depth,
          skeleton: const TreeGenerator().generate(
            rules: oakForm.rules,
            seed: p.seed,
            growth01: p.g,
          ),
          form: oakForm,
          foliage: const FoliageState(),
          seed: p.seed,
        ),
    ];

    for (var i = 0; i < count; i++) {
      final spec = build(i);
      final cellRecorder = ui.PictureRecorder();
      final cellCanvas = Canvas(cellRecorder);
      ForestScene(atlas: atlas).paint(
        cellCanvas,
        Size(cellW.toDouble(), cellH.toDouble()),
        trees: placements,
        conditions: spec.conditions,
        timeOfDay01: spec.timeOfDay,
        timeSeconds: 4.2,
        worldSeed: 20260903,
      );
      final img = await cellRecorder.endRecording().toImage(cellW, cellH);
      canvas.drawImage(
        img,
        Offset(i * cellW.toDouble(), header.toDouble()),
        Paint(),
      );
      _text(
        canvas,
        spec.caption,
        Offset(i * cellW + 12.0, header + cellH - 24.0),
        14,
        const Color(0xFFF0F0EC),
      );
      img.dispose();
    }

    final out2 = await recorder.endRecording().toImage(w.toInt(), h.toInt());
    final data = await out2.toByteData(format: ui.ImageByteFormat.png);
    File('$out/$file').writeAsBytesSync(data!.buffer.asUint8List());
    out2.dispose();
    atlas.dispose();
  });

  WorldConditions conds(WeatherKind w, {bool night = false}) => WorldConditions(
    weather: w,
    lightLevel: 100 * w.light,
    temperature: 15,
    isNight: night,
    rainRate: w.rainPerHour,
  );

  testWidgets('day cycle', (t) async {
    const hours = [
      (0.27, 'dawn'),
      (0.36, 'morning'),
      (0.50, 'midday'),
      (0.66, 'afternoon'),
      (0.74, 'dusk'),
      (0.92, 'night'),
    ];
    await sheet(
      tester: t,
      file: 'w_day_cycle.png',
      label: 'A day in the plot — one palette drives sky, light and ground',
      count: hours.length,
      build: (i) => (
        conditions: conds(
          WeatherKind.sunny,
          night: hours[i].$1 > 0.83 || hours[i].$1 < 0.25,
        ),
        timeOfDay: hours[i].$1,
        caption: hours[i].$2,
      ),
    );
  });

  testWidgets('vitals to world', (t) async {
    // The whole chain in one row: only the tree's *vitals* differ between
    // cells. Everything visible is derived.
    const cases = <(String, double, double, double)>[
      ('water 58 · fed 52 · health 96', 58, 52, 96),
      ('water 24 · fed 52 · health 80', 24, 52, 80),
      ('water 92 · fed 52 · health 78', 92, 52, 78),
      ('water 58 · fed 8 · health 74', 58, 8, 74),
      ('water 58 · fed 92 · health 70', 58, 92, 70),
      ('water 20 · fed 14 · health 26', 20, 14, 26),
    ];
    await _vitalsSheet(t, cases);
  });

  testWidgets('weather', (t) async {
    const kinds = [
      WeatherKind.sunny,
      WeatherKind.cloudy,
      WeatherKind.rain,
      WeatherKind.storm,
      WeatherKind.fog,
      WeatherKind.snow,
    ];
    await sheet(
      tester: t,
      file: 'w_weather.png',
      label: 'Weather — the MVP ships the first three; the rest already work',
      count: kinds.length,
      build: (i) => (
        conditions: conds(kinds[i]),
        timeOfDay: 0.45,
        caption: kinds[i].label,
      ),
    );
  });
}

/// Renders trees whose appearance comes from vitals via the real projector.
Future<void> _vitalsSheet(
  WidgetTester tester,
  List<(String, double, double, double)> cases,
) => tester.runAsync(() async {
  Directory('build/art_review').createSync(recursive: true);
  await _loadFont();
  final atlas = await CanopyAtlas.decode(
    File('assets/canopy_oak.png').readAsBytesSync(),
  );
  final content = mvpContent();
  final projector = WorldProjector(content: content);
  final species = content[const SpeciesId('quercus_robur')];

  const cellW = 300, cellH = 380, header = 44;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final w = (cases.length * cellW).toDouble();
  final h = (cellH + header).toDouble();
  canvas.drawRect(
    Rect.fromLTWH(0, 0, w, h),
    Paint()..color = const Color(0xFFF4F5F3),
  );
  _text(
    canvas,
    'Vitals to appearance — only water, nutrition and health differ',
    const Offset(16, 12),
    19,
    const Color(0xFF191E1B),
  );

  const conditions = WorldConditions(
    weather: WeatherKind.sunny,
    lightLevel: 100,
    temperature: 16,
    isNight: false,
    rainRate: 0,
  );

  for (var i = 0; i < cases.length; i++) {
    final (caption, water, nutrition, health) = cases[i];
    final tree =
        Tree.seedling(
          id: const TreeId('t'),
          species: const SpeciesId('quercus_robur'),
          seed: const Seed(4242),
          slot: 0,
          plantedAt: SimTime.zero,
        ).copyWith(
          water: Vital(water),
          nutrition: Vital(nutrition),
          health: Vital(health),
          stage: GrowthStage.mature,
        );
    final comfort = Comfort.evaluate(
      tree: tree,
      species: species,
      conditions: conditions,
    );
    final foliage = projector.foliageFor(tree, species, conditions, comfort);

    final cell = ui.PictureRecorder();
    ForestScene(atlas: atlas).paint(
      Canvas(cell),
      Size(cellW.toDouble(), cellH.toDouble()),
      trees: [
        TreePlacement(
          id: const TreeId('t'),
          groundX: 0.5,
          depth: 0,
          skeleton: const TreeGenerator().generate(
            rules: oakForm.rules,
            seed: 4242,
            growth01: 0.88,
          ),
          form: oakForm,
          foliage: foliage,
          seed: 4242,
        ),
      ],
      conditions: conditions,
      timeOfDay01: 0.45,
      timeSeconds: 2.0,
      worldSeed: 99,
    );
    final img = await cell.endRecording().toImage(cellW, cellH);
    canvas.drawImage(
      img,
      Offset(i * cellW.toDouble(), header.toDouble()),
      Paint(),
    );
    _text(
      canvas,
      caption,
      Offset(i * cellW + 10.0, header + cellH - 24.0),
      13,
      const Color(0xFFF0F0EC),
    );
    img.dispose();
  }

  final out = await recorder.endRecording().toImage(w.toInt(), h.toInt());
  final data = await out.toByteData(format: ui.ImageByteFormat.png);
  File(
    'build/art_review/w_vitals_to_world.png',
  ).writeAsBytesSync(data!.buffer.asUint8List());
  out.dispose();
  atlas.dispose();
});

Future<void> _loadFont() async {
  for (final p in const [
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/System/Library/Fonts/Helvetica.ttc',
  ]) {
    final f = File(p);
    if (f.existsSync()) {
      await ui.loadFontFromList(f.readAsBytesSync(), fontFamily: 'ReviewSans');
      return;
    }
  }
}

void _text(Canvas c, String s, Offset at, double size, Color colour) {
  (TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(color: colour, fontSize: size, fontFamily: 'ReviewSans'),
    ),
    textDirection: TextDirection.ltr,
  )..layout()).paint(c, at);
}
