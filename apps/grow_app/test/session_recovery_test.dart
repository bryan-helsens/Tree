import 'package:flutter_test/flutter_test.dart';
import 'package:grow_app/game/game_controller.dart';
import 'package:grow_app/game/time_authority.dart';
import 'package:grow_content/grow_content.dart';
import 'package:grow_data/grow_data.dart';
import 'package:grow_domain/grow_domain.dart';
import 'package:grow_sim/grow_sim.dart';

/// Crash recovery, through real persistence.
///
/// Every "relaunch" below throws the controller away and builds a new one over
/// the same store and clock — which is what a process death actually is.
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

  /// A launch: a brand-new controller over the same disk and the same clock.
  Future<GameController> launch(
    SaveRepository store,
    FakeTimeAuthority clock, {
    GameState? seed,
  }) async {
    final c = GameController(
      content: content,
      initial: seed ?? fresh(),
      repository: store,
      clock: clock,
    );
    await c.resume();
    return c;
  }

  group('an ordinary session, uninterrupted', () {
    test('completes and pays once', () async {
      final store = GuardedSaveRepository(InMemorySaveRepository());
      final clock = FakeTimeAuthority();
      var game = await launch(store, clock);

      expect(await game.startSession(const Duration(minutes: 30)), isNull);
      expect(game.session!.phase, FocusPhase.running);

      clock.advance(const Duration(minutes: 31));
      game = await launch(store, clock);

      expect(game.session!.phase, FocusPhase.claimed);
      expect(game.lastReturn.sessionOutcome, isNotNull);
      expect(game.state.inventory.water, greaterThan(5));
    });
  });

  group('the process dies mid-session', () {
    test('the session survives and finishes on the next launch', () async {
      final store = GuardedSaveRepository(InMemorySaveRepository());
      final clock = FakeTimeAuthority();
      var game = await launch(store, clock);
      await game.startSession(const Duration(minutes: 45));
      final id = game.session!.id;

      // Process dies here. Nothing runs. Time passes anyway.
      clock.advance(const Duration(minutes: 50));
      game = await launch(store, clock);

      expect(game.session!.id, id, reason: 'the same session, not a new one');
      expect(game.session!.phase, FocusPhase.claimed);
      expect(game.session!.outcome!.actual, const Duration(minutes: 45));
    });

    test('relaunching ten times still pays once', () async {
      final store = GuardedSaveRepository(InMemorySaveRepository());
      final clock = FakeTimeAuthority();
      var game = await launch(store, clock);
      await game.startSession(const Duration(minutes: 20));

      clock.advance(const Duration(minutes: 25));
      game = await launch(store, clock);
      final water = game.state.inventory.water;
      final xp = game.state.progression.xp;

      for (var i = 0; i < 10; i++) {
        game = await launch(store, clock);
      }
      expect(game.state.inventory.water, water);
      expect(game.state.progression.xp, xp);
    });

    test('a crash between reward and record cannot happen', () async {
      // The reward and the claimed phase are fields of one value, so the only
      // states a save can hold are "neither" or "both".
      final store = InMemorySaveRepository();
      final clock = FakeTimeAuthority();
      var game = await launch(store, clock);
      await game.startSession(const Duration(minutes: 20));
      clock.advance(const Duration(minutes: 21));
      game = await launch(store, clock);

      final onDisk = await store.load();
      final claimed = onDisk!.session!.phase == FocusPhase.claimed;
      final paid = onDisk.progression.xp > 0;
      expect(claimed, paid, reason: 'never one without the other');
    });
  });

  group('the phone restarts', () {
    test('a session still completes across a reboot', () async {
      final store = GuardedSaveRepository(InMemorySaveRepository());
      final clock = FakeTimeAuthority();
      var game = await launch(store, clock);
      await game.startSession(const Duration(minutes: 30));

      clock.reboot(off: const Duration(minutes: 40));
      game = await launch(store, clock);

      expect(game.session!.phase, FocusPhase.claimed);
      expect(
        game.state.clock.anomalies,
        greaterThan(0),
        reason: 'the reboot was noticed',
      );
    });

    test('a reboot cannot be used to fabricate days of growth', () async {
      final store = GuardedSaveRepository(InMemorySaveRepository());
      final clock = FakeTimeAuthority();
      var game = await launch(store, clock);
      final before = game.state.simTime;

      clock.reboot(off: const Duration(days: 400));
      game = await launch(store, clock);

      final credited = game.state.simTime.ms - before.ms;
      expect(credited, lessThanOrEqualTo(const ClockGuard().maxResumeMs));
    });
  });

  group('the clock is tampered with', () {
    test('winding forward does not finish a session', () async {
      final store = GuardedSaveRepository(InMemorySaveRepository());
      final clock = FakeTimeAuthority();
      var game = await launch(store, clock);
      await game.startSession(const Duration(minutes: 60));

      // Only the wall clock moves; the device was awake for one minute.
      clock.advance(const Duration(minutes: 1));
      clock.skewWallClock(const Duration(days: 3));
      game = await launch(store, clock);

      expect(
        game.session!.phase,
        FocusPhase.running,
        reason: 'a minute of real time is a minute of session',
      );
    });

    test('winding backwards loses nothing', () async {
      final store = GuardedSaveRepository(InMemorySaveRepository());
      final clock = FakeTimeAuthority();
      var game = await launch(store, clock);
      await game.startSession(const Duration(minutes: 30));

      clock.advance(const Duration(minutes: 20));
      game = await launch(store, clock);
      final progressed = game.session!.elapsedAt(game.state.simTime);

      clock.skewWallClock(const Duration(days: -7));
      game = await launch(store, clock);

      expect(
        game.session!.elapsedAt(game.state.simTime),
        greaterThanOrEqualTo(progressed),
        reason: 'progress already made is not undone',
      );
      expect(game.session!.phase, FocusPhase.running);
    });

    test('a restored older save cannot re-earn its time', () async {
      final store = InMemorySaveRepository();
      final clock = FakeTimeAuthority();
      var game = await launch(store, clock);

      clock.advance(const Duration(hours: 6));
      game = await launch(store, clock);
      final reached = game.state.simTime.ms;
      final high = game.state.clock.simTimeHighMs;

      // Roll the save back, keeping the watermark that outlives it.
      await store.save(
        fresh().copyWith(
          simTime: const SimTime(0),
          clock: game.state.clock.copyWith(simTimeHighMs: high),
        ),
      );
      game = await launch(store, clock);
      expect(game.state.simTime.ms, greaterThanOrEqualTo(reached - 60000));
    });
  });

  group('ending early', () {
    test('pays for the time spent and persists', () async {
      final store = GuardedSaveRepository(InMemorySaveRepository());
      final clock = FakeTimeAuthority();
      var game = await launch(store, clock);
      await game.startSession(const Duration(minutes: 60));

      clock.advance(const Duration(minutes: 15));
      game = await launch(store, clock);
      await game.endSessionEarly();

      expect(game.session!.phase, FocusPhase.claimed);
      expect(game.session!.outcome!.growthPoints, greaterThan(0));

      // And it stays paid across a relaunch.
      final xp = game.state.progression.xp;
      game = await launch(store, clock);
      expect(game.state.progression.xp, xp);
    });
  });

  group('the reward reaches the tree through the simulation', () {
    test('growth is injected, and appearance follows', () async {
      final store = GuardedSaveRepository(InMemorySaveRepository());
      final clock = FakeTimeAuthority();
      var game = await launch(store, clock);
      final before = game.state.trees.first;
      final beforeGrowth = before.stage.index * 100 + before.growth.value;

      await game.startSession(const Duration(minutes: 45));
      clock.advance(const Duration(minutes: 46));
      game = await launch(store, clock);

      final after = game.state.trees.first;
      final afterGrowth = after.stage.index * 100 + after.growth.value;
      expect(afterGrowth, greaterThan(beforeGrowth));

      // And the renderer's view of the tree came from the projection, not
      // from the focus screen.
      expect(game.snapshot.trees.first.growth01, greaterThan(0));
    });

    test('the focus flow never touches the tree directly', () async {
      // A session that is started but not finished changes no tree at all.
      final store = GuardedSaveRepository(InMemorySaveRepository());
      final clock = FakeTimeAuthority();
      final game = await launch(store, clock);
      final before = game.state.trees.first.growth.value;
      await game.startSession(const Duration(minutes: 30));
      expect(game.state.trees.first.growth.value, before);
    });
  });

  group('dismissal', () {
    test('clears the record and allows another session', () async {
      final store = GuardedSaveRepository(InMemorySaveRepository());
      final clock = FakeTimeAuthority();
      var game = await launch(store, clock);
      await game.startSession(const Duration(minutes: 10));
      clock.advance(const Duration(minutes: 11));
      game = await launch(store, clock);

      expect(
        await game.startSession(const Duration(minutes: 10)),
        isNotNull,
        reason: 'not while an unacknowledged session is on record',
      );
      await game.dismissSession();
      expect(game.session, isNull);
      expect(await game.startSession(const Duration(minutes: 10)), isNull);
    });
  });

  group('resume is idempotent', () {
    // Not the same as relaunching: this is one controller, asked to resume
    // more than once — a lifecycle callback firing twice, a retry after an
    // ambiguous failure, a hot restart.
    test('calling it repeatedly credits nothing extra', () async {
      final store = GuardedSaveRepository(InMemorySaveRepository());
      final clock = FakeTimeAuthority();
      final game = await launch(store, clock);

      clock.advance(const Duration(hours: 3));
      await game.resume();

      final afterFirst = game.state;
      expect(afterFirst.simTime.ms, greaterThan(0));

      // No clock movement between them, so there is no time to credit.
      await game.resume();
      await game.resume();

      expect(game.state.simTime.ms, afterFirst.simTime.ms);
      expect(
        game.state.trees.first.growth.value,
        afterFirst.trees.first.growth.value,
      );
      expect(game.state.inventory.water, afterFirst.inventory.water);
    });

    test(
      'a finished session is claimed once across repeated resumes',
      () async {
        final store = GuardedSaveRepository(InMemorySaveRepository());
        final clock = FakeTimeAuthority();
        final game = await launch(store, clock);

        await game.startSession(const Duration(minutes: 30));
        clock.advance(const Duration(minutes: 31));

        await game.resume();
        final water = game.state.inventory.water;
        final outcome = game.lastReturn.sessionOutcome;
        expect(outcome, isNotNull);

        await game.resume();
        await game.resume();

        expect(game.state.inventory.water, water, reason: 'paid twice');
        expect(game.state.session!.phase, FocusPhase.claimed);
      },
    );
  });

  group('a session is exactly one growth transaction', () {
    test('the injection lands once, however many times we relaunch', () async {
      final store = GuardedSaveRepository(InMemorySaveRepository());
      final clock = FakeTimeAuthority();
      var game = await launch(store, clock);

      await game.startSession(const Duration(minutes: 45));
      clock.advance(const Duration(minutes: 46));

      // The launch that claims it.
      game = await launch(store, clock);
      final injected = game.lastReturn.sessionOutcome!.growthInjection;
      expect(injected, greaterThan(0));
      final absolute = _absoluteGrowth(game.state.trees.first);

      // Relaunch twice more with the clock frozen: no simulated time passes,
      // so any movement at all would be a second injection.
      game = await launch(store, clock);
      expect(_absoluteGrowth(game.state.trees.first), closeTo(absolute, 1e-9));

      game = await launch(store, clock);
      expect(_absoluteGrowth(game.state.trees.first), closeTo(absolute, 1e-9));
      expect(game.lastReturn.sessionOutcome, isNull, reason: 'claimed again');
    });

    test('growth crossing a stage boundary is carried, not clipped', () async {
      final store = GuardedSaveRepository(InMemorySaveRepository());
      final clock = FakeTimeAuthority();
      final almost = fresh();
      var game = await launch(
        store,
        clock,
        seed: almost.copyWith(
          trees: [almost.trees.first.copyWith(growth: Vital(98))],
        ),
      );

      await game.startSession(const Duration(minutes: 45));
      clock.advance(const Duration(minutes: 46));
      game = await launch(store, clock);

      final tree = game.state.trees.first;
      // It moved on rather than parking at 100 with the remainder discarded.
      expect(tree.stage, GrowthStage.young);
      expect(tree.growth.value, lessThan(100));
    });
  });

  group('a fully grown tree', () {
    test('is paid, but gains no phantom progression', () async {
      final store = GuardedSaveRepository(InMemorySaveRepository());
      final clock = FakeTimeAuthority();
      final base = fresh();
      var game = await launch(
        store,
        clock,
        seed: base.copyWith(
          trees: [
            base.trees.first.copyWith(
              stage: GrowthStage.ancient,
              growth: Vital.zero,
            ),
          ],
        ),
      );

      final waterBefore = game.state.inventory.water;
      await game.startSession(const Duration(minutes: 45));
      clock.advance(const Duration(minutes: 46));
      game = await launch(store, clock);

      final outcome = game.lastReturn.sessionOutcome!;
      // The completion screen must not promise growth the tree cannot make.
      expect(outcome.growthInjection, 0);
      // And no invisible counter creeps up behind it.
      expect(game.state.trees.first.stage, GrowthStage.ancient);
      expect(game.state.trees.first.growth.value, 0);
      // Everything else is still earned. The time was still spent.
      expect(game.state.inventory.water, greaterThan(waterBefore));
      expect(outcome.xp, greaterThan(0));
    });
  });

  group('the return summary', () {
    test('reports the away time and what happened', () async {
      final store = GuardedSaveRepository(InMemorySaveRepository());
      final clock = FakeTimeAuthority();
      var game = await launch(store, clock);

      clock.advance(const Duration(hours: 9));
      game = await launch(store, clock);

      expect(game.lastReturn.isWorthShowing, isTrue);
      expect(
        game.lastReturn.away,
        greaterThanOrEqualTo(const Duration(hours: 8)),
      );
      expect(game.lastReturn.dewGained, greaterThan(0));
    });

    test('a brief absence is not worth interrupting anyone for', () async {
      final store = GuardedSaveRepository(InMemorySaveRepository());
      final clock = FakeTimeAuthority();
      var game = await launch(store, clock);
      clock.advance(const Duration(minutes: 3));
      game = await launch(store, clock);
      expect(game.lastReturn.isWorthShowing, isFalse);
    });
  });
}

/// Stage plus progress within it, so a stage-up is not read as a reset.
double _absoluteGrowth(Tree t) => t.stage.index * 100.0 + t.growth.value;
