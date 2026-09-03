import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_domain/grow_domain.dart';
import 'package:grow_flora/grow_flora.dart';
import 'package:grow_render/grow_render.dart';

/// The world is a canvas, which is invisible to a screen reader unless we
/// build a parallel semantic tree. These tests are what keep that true.
void main() {
  ForestTree tree(
    String id, {
    double x = 0.5,
    double depth = 0,
    double g = 0.9,
  }) => ForestTree(
    id: TreeId(id),
    skeleton: const TreeGenerator().generate(
      rules: oakForm.rules,
      seed: 4242,
      growth01: g,
    ),
    form: oakForm,
    foliage: const FoliageState(),
    groundX: x,
    depth: depth,
    seed: 4242,
    semanticLabel: 'Pedunculate Oak, mature tree',
    semanticValue: 'Healthy. Water 62 of an ideal 45 to 70.',
  );

  const conditions = WorldConditions(
    weather: WeatherKind.sunny,
    lightLevel: 100,
    temperature: 16,
    isNight: false,
    rainRate: 0,
  );

  Widget host(List<ForestTree> trees, {void Function(TreeId)? onTap}) =>
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(800, 600)),
          child: SizedBox(
            width: 800,
            height: 600,
            child: ForestView(
              trees: trees,
              conditions: conditions,
              timeOfDay01: 0.5,
              timeSeconds: 0,
              worldSeed: 1,
              onTapTree: onTap,
            ),
          ),
        ),
      );

  testWidgets('every tree gets a labelled, tappable semantic node', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      host([tree('a', x: 0.3), tree('b', x: 0.7)], onTap: (_) {}),
    );

    expect(
      find.bySemanticsLabel('Pedunculate Oak, mature tree'),
      findsNWidgets(2),
    );

    final node = tester.getSemantics(
      find.bySemanticsLabel('Pedunculate Oak, mature tree').first,
    );
    expect(node.value, contains('ideal 45 to 70'));
    expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    handle.dispose();
  });

  testWidgets('tapping a tree reports which one', (tester) async {
    TreeId? tapped;
    await tester.pumpWidget(
      host([
        tree('a', x: 0.25),
        tree('b', x: 0.75),
      ], onTap: (id) => tapped = id),
    );
    await tester.tap(
      find.bySemanticsLabel('Pedunculate Oak, mature tree').last,
    );
    expect(tapped, const TreeId('b'));
  });

  testWidgets('a seedling is still reachable', (tester) async {
    // A tree at the start of its life is a few pixels tall. Its touch target
    // must not be.
    const size = Size(800, 600);
    final seedling = tree('tiny', g: 0.05);
    final rect = ForestView.treeRect(seedling, size);
    expect(rect.width, greaterThanOrEqualTo(ForestView.minimumTapTarget));
    expect(rect.height, greaterThanOrEqualTo(ForestView.minimumTapTarget));
  });

  testWidgets('the semantic node sits over where the tree is drawn', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host([tree('a', x: 0.25)]));
    final rect = tester.getRect(
      find.bySemanticsLabel('Pedunculate Oak, mature tree'),
    );
    // Centred near the tree's ground position, and standing on the ground
    // rather than floating.
    expect(rect.center.dx, closeTo(800 * 0.25, 90));
    expect(rect.bottom, greaterThan(600 * ForestScene.groundFraction - 1));
    handle.dispose();
  });

  testWidgets('placement has exactly one implementation', (tester) async {
    // The painter and the accessibility layer must agree on where a tree is,
    // or every semantic node sits somewhere the tree is not. They did drift
    // once: the painter kept its own copy of this arithmetic and the two
    // diverged silently. This pins them to the same call.
    const size = Size(800, 600);
    for (final depth in [0.0, 0.35, 0.8]) {
      for (final x in [0.2, 0.5, 0.9]) {
        final t = tree('a', x: x, depth: depth);
        final where = ForestScene.placeTree(size, x, depth);
        final rect = ForestView.treeRect(t, size);
        final b = t.skeleton.bounds;

        // The drawn tree's foot is the semantic node's bottom edge, and its
        // horizontal centre matches, up to the minimum-target expansion.
        expect(rect.bottom, closeTo(where.baseY, 0.001));
        final drawnWidth = (b.maxX - b.minX) * where.scale;
        if (drawnWidth >= ForestView.minimumTapTarget) {
          expect(rect.left, closeTo(where.x + b.minX * where.scale, 0.001));
          expect(rect.right, closeTo(where.x + b.maxX * where.scale, 0.001));
        }
      }
    }
  });

  testWidgets('a distant tree is drawn smaller than a near one', (
    tester,
  ) async {
    const size = Size(800, 600);
    final near = ForestView.treeRect(tree('n', depth: 0), size);
    final far = ForestView.treeRect(tree('f', depth: 0.8), size);
    expect(far.height, lessThan(near.height));
  });

  testWidgets('reduced motion calms the wind without freezing the world', (
    tester,
  ) async {
    // Going fully static would remove the thing the player is here for.
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(
            size: Size(800, 600),
            disableAnimations: true,
          ),
          child: SizedBox(
            width: 800,
            height: 600,
            child: ForestView(
              trees: [tree('a')],
              conditions: conditions,
              timeOfDay01: 0.5,
              timeSeconds: 1,
              worldSeed: 1,
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders through a full day and every weather without throwing', (
    tester,
  ) async {
    for (final weather in WeatherKind.values) {
      for (final hour in [0.0, 0.25, 0.5, 0.75]) {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: const MediaQueryData(size: Size(800, 600)),
              child: SizedBox(
                width: 800,
                height: 600,
                child: ForestView(
                  trees: [tree('a')],
                  conditions: WorldConditions(
                    weather: weather,
                    lightLevel: 100 * weather.light,
                    temperature: 14,
                    isNight: hour < 0.25,
                    rainRate: weather.rainPerHour,
                  ),
                  timeOfDay01: hour,
                  timeSeconds: 3,
                  worldSeed: 7,
                ),
              ),
            ),
          ),
        );
        expect(
          tester.takeException(),
          isNull,
          reason: '${weather.name} at hour $hour',
        );
      }
    }
  });
}
