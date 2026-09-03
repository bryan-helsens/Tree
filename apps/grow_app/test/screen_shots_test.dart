import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_app/features/forest/forest_screen.dart';
import 'package:grow_app/game/game_controller.dart';
import 'package:grow_app/game/game_providers.dart';
import 'package:grow_content/grow_content.dart';
import 'package:grow_domain/grow_domain.dart';

/// Captures the real screen, so the interface is reviewed rather than assumed.
///   flutter test test/screen_shots_test.dart
const shotKey = ValueKey('screenshot');

void main() {
  const out = 'build/screens';
  final content = mvpContent();

  setUpAll(_loadFont);

  GameController controllerWith({
    required double water,
    required double nutrition,
    required double health,
    GrowthStage stage = GrowthStage.mature,
    int waterStock = 7,
    int nutrientStock = 3,
    int level = 4,
    int streak = 3,
  }) {
    final base = GameState.newGame(
      worldSeed: const Seed(20260903),
      starterSpecies: const SpeciesId('quercus_robur'),
    );
    return GameController(
      content: content,
      initial: base.copyWith(
        simTime: SimTime(SimTime.hourMs * 10),
        trees: [
          base.trees.first.copyWith(
            stage: stage,
            growth: Vital(62),
            water: Vital(water),
            nutrition: Vital(nutrition),
            health: Vital(health),
          ),
        ],
        inventory: Inventory.starting().copyWith(
          water: waterStock,
          waterCap: 19,
          nutrients: nutrientStock,
          nutrientCap: 6,
        ),
        progression: const Progression.starting().copyWith(
          level: level,
          xp: 320,
          focusStreakDays: streak,
        ),
      ),
    );
  }

  Future<void> shoot(
    WidgetTester tester,
    String name,
    GameController controller, {
    bool openSheet = false,
  }) async {
    Directory(out).createSync(recursive: true);
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [gameControllerProvider.overrideWith((ref) => controller)],
        child: const DefaultTextStyle(
          style: TextStyle(fontFamily: 'ReviewSans'),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: MediaQueryData(size: Size(360, 720), devicePixelRatio: 3),
              child: RepaintBoundary(key: shotKey, child: ForestScreen()),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    if (openSheet) {
      await tester.tap(find.bySemanticsLabel(RegExp('Pedunculate Oak')).first);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 900));
    }

    final image = await _capture(tester);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  }

  testWidgets('forest with hud', (t) async {
    await shoot(
      t,
      'forest_hud',
      controllerWith(water: 58, nutrition: 52, health: 94),
    );
  });

  testWidgets('tree panel healthy', (t) async {
    await shoot(
      t,
      'panel_healthy',
      controllerWith(water: 58, nutrition: 52, health: 94),
      openSheet: true,
    );
  });

  testWidgets('tree panel thirsty', (t) async {
    await shoot(
      t,
      'panel_thirsty',
      controllerWith(water: 26, nutrition: 44, health: 68),
      openSheet: true,
    );
  });

  testWidgets('tree panel overfed', (t) async {
    final c = controllerWith(water: 60, nutrition: 88, health: 58);
    c.advanceTo(SimTime(c.state.simTime.ms + SimTime.hourMs * 2));
    await shoot(t, 'panel_overfed', c, openSheet: true);
  });

  testWidgets('tree panel no resources', (t) async {
    final c = controllerWith(
      water: 30,
      nutrition: 40,
      health: 70,
      waterStock: 0,
      nutrientStock: 0,
    );
    await shoot(t, 'panel_empty', c, openSheet: true);
  });
}

/// flutter_test ships the Ahem placeholder font, which draws every glyph as a
/// filled box. Load a real face and name it in the harness's DefaultTextStyle;
/// the design system's styles leave `fontFamily` null, so they inherit it.
Future<void> _loadFont() async {
  for (final path in const [
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/System/Library/Fonts/Helvetica.ttc',
  ]) {
    final f = File(path);
    if (f.existsSync()) {
      final bytes = f.readAsBytesSync();
      // Loading it *as* Ahem is the trick: every style that does not name a
      // family resolves to the test binding's default, which is Ahem.
      await ui.loadFontFromList(bytes, fontFamily: 'ReviewSans');
      return;
    }
  }
}

Future<ui.Image> _capture(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(shotKey),
  );
  return boundary.toImage(pixelRatio: 2);
}
