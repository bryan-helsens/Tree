import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_app/features/forest/forest_screen.dart';
import 'package:grow_app/features/forest/hud.dart';
import 'package:grow_app/game/game_controller.dart';
import 'package:grow_app/game/game_providers.dart';
import 'package:grow_app/game/time_authority.dart';
import 'package:grow_content/grow_content.dart';
import 'package:grow_data/grow_data.dart';
import 'package:grow_domain/grow_domain.dart';
import 'package:grow_flora/grow_flora.dart';
import 'package:grow_render/grow_render.dart';

/// The whole screen, end to end: tap the call, choose, begin, come back.
///
/// The canopy atlas is left permanently loading. `ForestScreen` reads it with
/// `valueOrNull` and draws without it, so the interface under test is exactly
/// the shipping one minus the leaf sprites — and no image decode runs inside
/// the fake-async zone, which is what wedges the screenshot harness.
void main() {
  final content = mvpContent();

  GameState fresh() {
    final base = GameState.newGame(
      worldSeed: const Seed(20260903),
      starterSpecies: const SpeciesId('quercus_robur'),
    );
    return base.copyWith(
      trees: [
        base.trees.first.copyWith(
          stage: GrowthStage.sapling,
          water: Vital(58),
          nutrition: Vital(52),
          health: Vital(92),
        ),
      ],
      inventory: const Inventory.starting().copyWith(water: 5, nutrients: 2),
    );
  }

  var launchCount = 0;

  ({Widget widget, GameController controller}) build({
    required SaveRepository store,
    required FakeTimeAuthority clock,
    GameState? seed,
  }) {
    // A distinct key per launch. Without it Flutter updates the existing
    // element in place — same widget type — and `initState` never runs again,
    // so the new controller's resume() is never called. That is not a
    // relaunch; it is the old screen wearing new providers.
    final key = ValueKey('launch-${launchCount++}');
    final controller = GameController(
      content: content,
      initial: seed ?? fresh(),
      repository: store,
      clock: clock,
    );
    return (
      controller: controller,
      widget: ProviderScope(
        key: key,
        overrides: [
          gameControllerProvider.overrideWith((ref) => controller),
          canopyAtlasProvider.overrideWith(
            (ref) => Completer<CanopyAtlas>().future,
          ),
        ],
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: MediaQueryData(size: Size(390, 844)),
            child: ForestScreen(),
          ),
        ),
      ),
    );
  }

  testWidgets('start a session from the forest, and it becomes domain state', (
    t,
  ) async {
    final store = GuardedSaveRepository(InMemorySaveRepository());
    final clock = FakeTimeAuthority();
    final app = build(store: store, clock: clock);

    await t.pumpWidget(app.widget);
    await t.pump();

    expect(app.controller.session, isNull);

    await t.tap(find.text('Put your phone down').last);
    await t.pump();
    expect(find.text('Begin'), findsOneWidget);

    await t.tap(find.text('45'));
    await t.pump();
    await t.tap(find.text('Begin'));
    await t.pump();
    await t.pump();

    // The session exists in the save, not in the widget.
    expect(app.controller.session!.phase, FocusPhase.running);
    expect(app.controller.session!.planned, const Duration(minutes: 45));
    expect(await store.load(), isNotNull);

    // And the surface followed the state, rather than the other way round.
    expect(find.text('min left'), findsOneWidget);
  });

  testWidgets('a session finished while away greets the player on return', (
    t,
  ) async {
    final store = GuardedSaveRepository(InMemorySaveRepository());
    final clock = FakeTimeAuthority();

    // First launch: begin a session, then the process dies.
    final first = build(store: store, clock: clock);
    await t.pumpWidget(first.widget);
    await t.pump();
    await first.controller.startSession(const Duration(minutes: 45));

    // Away for three hours. The app is not running.
    clock.advance(const Duration(hours: 3));

    // Relaunch: a brand-new controller over the same store and clock.
    final second = build(store: store, clock: clock);
    await t.pumpWidget(second.widget);
    await t.pump();
    await t.pump();

    // Nothing has been tapped, and the reward is already in the save.
    expect(second.controller.session!.phase, FocusPhase.claimed);
    expect(second.controller.state.inventory.water, greaterThan(5));

    // The return moment leads, and it speaks about the world.
    expect(find.text('While you were away'), findsOneWidget);
    expect(find.text('You were gone a few hours.'), findsOneWidget);

    // The forest call is out of the way while it is showing.
    expect(find.text('Put your phone down'), findsNothing);
  });

  testWidgets('the focus call does not linger behind an open sheet', (t) async {
    // The Week 5 "ghost focus call". Not a rendering artifact: `showCall` was
    // accepted by the HUD and never read, so the call rendered underneath
    // every sheet. This is the regression test for it.
    final store = GuardedSaveRepository(InMemorySaveRepository());
    final clock = FakeTimeAuthority();
    final app = build(store: store, clock: clock);

    await t.pumpWidget(app.widget);
    await t.pump();
    expect(find.text('Put your phone down'), findsOneWidget);

    await t.tap(find.text('Put your phone down').last);
    await t.pump();

    // The picker is up, so the call underneath it must be gone — not merely
    // covered.
    expect(find.text('Begin'), findsOneWidget);
    expect(find.text('Put your phone down'), findsOneWidget);
    expect(
      find.byType(ForestHud),
      findsOneWidget,
      reason: 'the HUD itself stays; only its call goes',
    );
    // The one remaining instance is the picker's own heading, inside the
    // sheet — not a second copy behind it.
    expect(
      find.descendant(
        of: find.byType(ForestHud),
        matching: find.text('Put your phone down'),
      ),
      findsNothing,
    );
  });

  testWidgets('the tree eases toward its new size rather than jumping', (
    t,
  ) async {
    final store = GuardedSaveRepository(InMemorySaveRepository());
    final clock = FakeTimeAuthority();
    final app = build(store: store, clock: clock);

    await t.pumpWidget(app.widget);
    await t.pump();
    await t.pump();

    /// Total branch length of whatever the screen is currently drawing.
    double drawn() {
      final view = t.widget<ForestView>(find.byType(ForestView));
      return view.trees.first.skeleton.branches
          .map((b) => b.length)
          .reduce((a, b) => a + b);
    }

    /// The same measurement, for a tree generated at [growth01].
    double at(double growth01) {
      final visual = app.controller.snapshot.trees.first;
      return const TreeGenerator()
          .generate(
            rules: formFor(visual.speciesId.raw).rules,
            seed: visual.seed,
            growth01: growth01,
          )
          .branches
          .map((b) => b.length)
          .reduce((a, b) => a + b);
    }

    final before = drawn();

    // A long absence, so the tree's size moves by an amount a player would
    // actually notice. A single session's injection is deliberately small;
    // this is the case where drawing the step directly would read as a pop.
    clock.advance(const Duration(hours: 30));
    await app.controller.resume();

    final target = at(app.controller.snapshot.trees.first.growth01);
    expect(
      target,
      greaterThan(before),
      reason: 'sanity: the tree really did get bigger',
    );

    // One frame later it has started moving and has not arrived.
    await t.pump(const Duration(milliseconds: 16));
    final oneFrame = drawn();
    expect(oneFrame, greaterThan(before), reason: 'it should be growing');
    expect(oneFrame, lessThan(target), reason: 'it jumped straight there');

    // Given time, it arrives.
    for (var i = 0; i < 400; i++) {
      await t.pump(const Duration(milliseconds: 16));
    }
    expect(drawn(), closeTo(target, target * 0.03));
  });
}
