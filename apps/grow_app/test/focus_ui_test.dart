import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_app/features/focus/focus_sheet.dart';
import 'package:grow_app/features/focus/welcome_back_sheet.dart';
import 'package:grow_app/game/focus_view.dart';
import 'package:grow_app/game/game_controller.dart';
import 'package:grow_app/game/return_summary.dart';
import 'package:grow_app/game/time_authority.dart';
import 'package:grow_content/grow_content.dart';
import 'package:grow_data/grow_data.dart';
import 'package:grow_domain/grow_domain.dart';
import 'package:grow_sim/grow_sim.dart';

/// The focus interface is a **projection of the save**, and these tests are
/// what keep it one. If a widget ever starts deciding whether a session is
/// running, or granting a reward, something here fails.
void main() {
  final content = mvpContent();

  GameState fresh() {
    final base = GameState.newGame(
      worldSeed: const Seed(20260903),
      starterSpecies: const SpeciesId('quercus_robur'),
    );
    return base.copyWith(
      trees: [base.trees.first.copyWith(stage: GrowthStage.sapling)],
      inventory: const Inventory.starting().copyWith(water: 5, nutrients: 2),
    );
  }

  Future<GameController> launch(
    SaveRepository store,
    FakeTimeAuthority clock,
  ) async {
    final c = GameController(
      content: content,
      initial: fresh(),
      repository: store,
      clock: clock,
    );
    await c.resume();
    return c;
  }

  Widget wrap(Widget child) => Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: const MediaQueryData(size: Size(390, 844)),
      child: Align(alignment: Alignment.bottomCenter, child: child),
    ),
  );

  group('FocusView is derived from the save, not from taps', () {
    test('no session reads as idle', () {
      expect(FocusView.of(fresh()), isA<FocusIdle>());
    });

    test('a running session carries its own progress', () {
      final machine = FocusMachine(content: content);
      final started = machine
          .start(
            fresh(),
            planned: const Duration(minutes: 30),
            id: 's1',
            wallMs: 0,
          )
          .state!;

      final halfway = started.copyWith(
        simTime: SimTime(started.simTime.ms + 15 * 60 * 1000),
      );

      final view = FocusView.of(halfway) as FocusRunning;
      expect(view.progress, closeTo(0.5, 1e-9));
      expect(view.minutesLeft, 15);
    });

    test('minutes are rounded up, never shown as seconds', () {
      final machine = FocusMachine(content: content);
      final started = machine
          .start(
            fresh(),
            planned: const Duration(minutes: 30),
            id: 's1',
            wallMs: 0,
          )
          .state!;
      // 29 minutes 1 second gone: 59 seconds left is "1", never "0".
      final nearlyDone = started.copyWith(
        simTime: SimTime(started.simTime.ms + (29 * 60 + 1) * 1000),
      );
      expect((FocusView.of(nearlyDone) as FocusRunning).minutesLeft, 1);
    });

    test('a claimed session reports the committed outcome', () async {
      final store = GuardedSaveRepository(InMemorySaveRepository());
      final clock = FakeTimeAuthority();
      final game = await launch(store, clock);
      await game.startSession(const Duration(minutes: 30));
      clock.advance(const Duration(minutes: 31));
      await game.resume();

      final view = FocusView.of(game.state) as FocusFinished;
      expect(view.outcome, same(game.session!.outcome));
      expect(view.endedEarly, isFalse);
    });
  });

  group('the completion panel', () {
    testWidgets('appears without anyone tapping anything', (t) async {
      final store = GuardedSaveRepository(InMemorySaveRepository());
      final clock = FakeTimeAuthority();
      final game = await launch(store, clock);
      await game.startSession(const Duration(minutes: 30));

      // The player is not here. The app is closed. Time passes.
      clock.advance(const Duration(minutes: 31));
      await game.resume();

      // First frame back — no gesture has been made.
      await t.pumpWidget(
        wrap(
          FocusSheet(
            view: FocusView.of(game.state),
            onStart: (_) => fail('the panel must not start anything'),
            onEndEarly: () => fail('nothing to end'),
            onDismiss: () {},
            onClose: () {},
          ),
        ),
      );

      expect(find.text('Your oak grew'), findsOneWidget);
    });

    testWidgets('reports the committed numbers, and grants nothing', (t) async {
      final store = GuardedSaveRepository(InMemorySaveRepository());
      final clock = FakeTimeAuthority();
      final game = await launch(store, clock);
      await game.startSession(const Duration(minutes: 30));
      clock.advance(const Duration(minutes: 31));
      await game.resume();

      final outcome = game.session!.outcome!;
      final waterBefore = game.state.inventory.water;

      await t.pumpWidget(
        wrap(
          FocusSheet(
            view: FocusView.of(game.state),
            onStart: (_) {},
            onEndEarly: () {},
            onDismiss: () {},
            onClose: () {},
          ),
        ),
      );

      expect(find.text('${outcome.water}'), findsOneWidget);
      // Building the panel changed nothing. It is a report.
      expect(game.state.inventory.water, waterBefore);
    });

    testWidgets('ending early is not framed as a failure', (t) async {
      final store = GuardedSaveRepository(InMemorySaveRepository());
      final clock = FakeTimeAuthority();
      final game = await launch(store, clock);
      await game.startSession(const Duration(minutes: 60));
      clock.advance(const Duration(minutes: 10));
      await game.resume();
      await game.endSessionEarly();

      await t.pumpWidget(
        wrap(
          FocusSheet(
            view: FocusView.of(game.state),
            onStart: (_) {},
            onEndEarly: () {},
            onDismiss: () {},
            onClose: () {},
          ),
        ),
      );

      expect(find.text('You came back'), findsOneWidget);
      expect(find.textContaining('every one of them counted'), findsOneWidget);
    });

    testWidgets('a fully grown tree is told the truth', (t) async {
      final base = fresh();
      final grown = base.copyWith(
        trees: [
          base.trees.first.copyWith(
            stage: GrowthStage.ancient,
            growth: Vital.zero,
          ),
        ],
      );
      final store = GuardedSaveRepository(InMemorySaveRepository());
      final clock = FakeTimeAuthority();
      final game = GameController(
        content: content,
        initial: grown,
        repository: store,
        clock: clock,
      );
      await game.resume();
      await game.startSession(const Duration(minutes: 30));
      clock.advance(const Duration(minutes: 31));
      await game.resume();

      await t.pumpWidget(
        wrap(
          FocusSheet(
            view: FocusView.of(game.state),
            onStart: (_) {},
            onEndEarly: () {},
            onDismiss: () {},
            onClose: () {},
          ),
        ),
      );

      // No growth line, because there was no growth — and a sentence that
      // says so, rather than a silent gap.
      expect(find.text('growth'), findsNothing);
      expect(find.textContaining('fully grown'), findsOneWidget);
    });
  });

  group('the picker', () {
    testWidgets('starts a session through the controller, not itself', (
      t,
    ) async {
      Duration? asked;
      await t.pumpWidget(
        wrap(
          FocusSheet(
            view: const FocusIdle(),
            onStart: (d) => asked = d,
            onEndEarly: () {},
            onDismiss: () {},
            onClose: () {},
          ),
        ),
      );

      await t.tap(find.text('45'));
      await t.pump();
      await t.tap(find.text('Begin'));

      expect(asked, const Duration(minutes: 45));
    });

    testWidgets('shows what a session pays before committing to it', (t) async {
      await t.pumpWidget(
        wrap(
          FocusSheet(
            view: const FocusIdle(),
            onStart: (_) {},
            onEndEarly: () {},
            onDismiss: () {},
            onClose: () {},
          ),
        ),
      );

      const economy = FocusEconomy();
      final at25 = economy.yieldFor(
        minutes: 25,
        sessionIndexToday: 0,
        streakDays: 0,
        gpAlreadyEarnedToday: 0,
      );
      expect(find.text('💧 ${at25.water}'), findsOneWidget);

      await t.tap(find.text('60'));
      await t.pump();

      final at60 = economy.yieldFor(
        minutes: 60,
        sessionIndexToday: 0,
        streakDays: 0,
        gpAlreadyEarnedToday: 0,
      );
      expect(find.text('💧 ${at60.water}'), findsOneWidget);
    });
  });

  group('the running panel', () {
    testWidgets('shows minutes, never a ticking countdown', (t) async {
      await t.pumpWidget(
        wrap(
          FocusSheet(
            view: const FocusRunning(
              planned: Duration(minutes: 30),
              elapsed: Duration(minutes: 10, seconds: 24),
              remaining: Duration(minutes: 19, seconds: 36),
              progress: 0.347,
            ),
            onStart: (_) {},
            onEndEarly: () {},
            onDismiss: () {},
            onClose: () {},
          ),
        ),
      );

      expect(find.text('20'), findsOneWidget);
      expect(find.text('min left'), findsOneWidget);
      // No seconds anywhere on the screen.
      expect(find.textContaining(':'), findsNothing);
    });

    testWidgets('says the session survives the app closing', (t) async {
      await t.pumpWidget(
        wrap(
          FocusSheet(
            view: const FocusRunning(
              planned: Duration(minutes: 30),
              elapsed: Duration(minutes: 1),
              remaining: Duration(minutes: 29),
              progress: 0.03,
            ),
            onStart: (_) {},
            onEndEarly: () {},
            onDismiss: () {},
            onClose: () {},
          ),
        ),
      );
      expect(find.textContaining('close the app'), findsOneWidget);
    });
  });

  group('the welcome back sheet', () {
    testWidgets('leads with the world, not with a productivity report', (
      t,
    ) async {
      final summary = ReturnSummary(
        away: const Duration(hours: 3),
        digest: null,
        journal: [
          const SimEvent(
            kind: SimEventKind.rainfall,
            at: SimTime(0),
            message: 'Rain came through in the afternoon',
          ),
          const SimEvent(
            kind: SimEventKind.growthStageUp,
            at: SimTime(1),
            message: 'Pedunculate Oak became a young tree',
          ),
        ],
      );

      await t.pumpWidget(
        wrap(WelcomeBackSheet(summary: summary, onDismiss: () {})),
      );

      expect(find.text('While you were away'), findsOneWidget);
      // Time in words, never a measurement.
      expect(find.text('You were gone a few hours.'), findsOneWidget);
      expect(find.textContaining('minutes'), findsNothing);
      expect(find.text('Pedunculate Oak became a young tree'), findsOneWidget);
    });

    testWidgets('the significant event outranks the weather', (t) async {
      final summary = ReturnSummary(
        away: const Duration(days: 2),
        digest: null,
        journal: [
          for (var i = 0; i < 8; i++)
            SimEvent(
              kind: SimEventKind.rainfall,
              at: SimTime(i),
              message: 'Rain shower $i',
            ),
          const SimEvent(
            kind: SimEventKind.growthStageUp,
            at: SimTime(99),
            message: 'Pedunculate Oak became a young tree',
          ),
        ],
      );

      await t.pumpWidget(
        wrap(WelcomeBackSheet(summary: summary, onDismiss: () {})),
      );

      // Buried ninth in the journal, but it is the thing that matters.
      expect(find.text('Pedunculate Oak became a young tree'), findsOneWidget);
    });

    testWidgets('a session is reported last and quietly', (t) async {
      final summary = ReturnSummary(
        away: const Duration(hours: 1),
        digest: null,
        journal: const [],
        sessionOutcome: const SessionOutcome(
          actual: Duration(minutes: 45),
          integrity: 1,
          growthPoints: 211,
          water: 4,
          nutrients: 2,
          xp: 211,
          growthInjection: 4.2,
          deepFocusBonus: true,
          levelsGained: 0,
        ),
      );

      await t.pumpWidget(
        wrap(WelcomeBackSheet(summary: summary, onDismiss: () {})),
      );

      expect(find.textContaining('brought back'), findsOneWidget);
      expect(find.text('💧 4'), findsOneWidget);
      // No XP, no growth points, no streak fanfare on this screen.
      expect(find.textContaining('211'), findsNothing);
      expect(find.textContaining('XP'), findsNothing);
    });
  });
}
