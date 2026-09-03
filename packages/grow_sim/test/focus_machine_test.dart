import 'package:grow_domain/grow_domain.dart';
import 'package:grow_sim/grow_sim.dart';
import 'package:test/test.dart';

import 'support.dart';

/// The focus session lifecycle, and the guarantees around it.
///
/// Answers the architecture questions in docs/22 as executable assertions:
/// which transitions exist, what happens across a crash or a reboot, and how
/// a reward is committed exactly once.
void main() {
  final machine = FocusMachine(content: content);

  GameState start(GameState s, {int minutes = 30, String id = 's1'}) {
    final t = machine.start(
      s,
      planned: Duration(minutes: minutes),
      id: id,
      wallMs: 1700000000000,
    );
    expect(t.ok, isTrue, reason: t.refusal?.message);
    return t.state!;
  }

  /// Advances simulated time the way a resume does: the guard has already
  /// vetted the interval, so this is what the simulator would have produced.
  GameState pass(GameState s, Duration d) {
    final advanced = sim()
        .run(state: s, to: SimTime(s.simTime.ms + d.inMilliseconds))
        .state;
    return machine.evaluate(advanced);
  }

  group('Q1/Q2 — states and legal transitions', () {
    test('a fresh save has no session', () {
      expect(newGame().session, isNull);
    });

    test('start creates a running session', () {
      final s = start(established());
      expect(s.session!.phase, FocusPhase.running);
      expect(s.session!.startedAt, s.simTime);
    });

    test('only one session at a time', () {
      final s = start(established());
      final again = machine.start(
        s,
        planned: const Duration(minutes: 20),
        id: 's2',
        wallMs: 0,
      );
      expect(again.ok, isFalse);
      expect(again.refusal, FocusRefusal.alreadyRunning);
    });

    test('duration is bounded at both ends', () {
      expect(
        machine
            .start(
              established(),
              planned: const Duration(minutes: 1),
              id: 'x',
              wallMs: 0,
            )
            .refusal,
        FocusRefusal.tooShort,
      );
      expect(
        machine
            .start(
              established(),
              planned: const Duration(hours: 9),
              id: 'x',
              wallMs: 0,
            )
            .refusal,
        FocusRefusal.tooLong,
      );
    });

    test('claiming a running session is refused', () {
      expect(
        machine.claim(start(established())).refusal,
        FocusRefusal.nothingToClaim,
      );
    });

    test('ending early is only possible while running', () {
      var s = start(established());
      s = machine.endEarly(s).state!;
      expect(s.session!.phase, FocusPhase.abandoned);
      expect(machine.endEarly(s).refusal, FocusRefusal.nothingRunning);
    });

    test('dismiss only clears a claimed session', () {
      var s = start(established());
      expect(machine.dismiss(s).refusal, FocusRefusal.nothingToClaim);
      s = machine.claim(pass(s, const Duration(minutes: 30))).state!;
      expect(machine.dismiss(s).state!.session, isNull);
    });

    test('a claimed session must be acknowledged before the next starts', () {
      var s = start(established());
      s = machine.claim(pass(s, const Duration(minutes: 30))).state!;
      expect(
        machine
            .start(s, planned: const Duration(minutes: 10), id: 's2', wallMs: 0)
            .refusal,
        FocusRefusal.awaitingAcknowledgement,
        reason: 'overwriting it would take away the completion moment',
      );
      s = machine.dismiss(s).state!;
      expect(
        machine
            .start(s, planned: const Duration(minutes: 10), id: 's2', wallMs: 0)
            .ok,
        isTrue,
      );
    });
  });

  group('Q7 — completion is a comparison, not a callback', () {
    test('a session completes when its planned time has elapsed', () {
      var s = start(established(), minutes: 30);
      s = pass(s, const Duration(minutes: 29));
      expect(s.session!.phase, FocusPhase.running);
      s = pass(s, const Duration(minutes: 2));
      expect(s.session!.phase, FocusPhase.completed);
    });

    test('it is credited at its planned end, not when it was noticed', () {
      // The process was dead for hours; the session still ends when it ended.
      var s = start(established(), minutes: 30);
      final plannedEnd =
          s.simTime.ms + const Duration(minutes: 30).inMilliseconds;
      s = pass(s, const Duration(hours: 9));
      expect(s.session!.finishedAt!.ms, plannedEnd);
      expect(s.session!.elapsedAt(s.simTime), const Duration(minutes: 30));
    });

    test('evaluate is idempotent', () {
      var s = pass(start(established()), const Duration(minutes: 31));
      final once = s.session!;
      s = machine.evaluate(machine.evaluate(s));
      expect(s.session!.phase, once.phase);
      expect(s.session!.finishedAt!.ms, once.finishedAt!.ms);
    });
  });

  group('Q3/Q4/Q5 — backgrounding, process death, reboot', () {
    test('a session needs nothing running to make progress', () {
      // Nothing here ticks. Progress is simTime minus startedAt, and the only
      // thing that moved simTime is the resume.
      var s = start(established(), minutes: 45);
      s = pass(s, const Duration(minutes: 50));
      expect(s.session!.phase, FocusPhase.completed);
    });

    test(
      'a session that ended while the process was dead pays on relaunch',
      () {
        var s = start(established(), minutes: 30);
        // Simulating a relaunch: the save is reloaded and time is credited.
        s = pass(s, const Duration(hours: 3));
        expect(s.session!.phase, FocusPhase.completed);

        final claimed = machine.claim(s);
        expect(claimed.ok, isTrue);
        expect(claimed.outcome!.water, greaterThan(0));
      },
    );
  });

  group('Q8/Q9 — the reward is committed exactly once', () {
    test('a claim moves the reward and the phase in one state', () {
      final before = pass(start(established()), const Duration(minutes: 31));
      final after = machine.claim(before).state!;

      // Both halves are present in the same value. There is no intermediate
      // state in which one happened and the other did not.
      expect(after.session!.phase, FocusPhase.claimed);
      expect(after.inventory.water, greaterThan(before.inventory.water));
      expect(after.progression.xp, greaterThan(before.progression.xp));
    });

    test('claiming twice pays once', () {
      var s = pass(start(established()), const Duration(minutes: 31));
      final first = machine.claim(s);
      s = first.state!;
      final water = s.inventory.water;
      final xp = s.progression.xp;

      final second = machine.claim(s);
      expect(second.ok, isTrue, reason: 'a retry must be safe, not an error');
      expect(second.state!.inventory.water, water);
      expect(second.state!.progression.xp, xp);
      expect(second.outcome!.growthPoints, first.outcome!.growthPoints);
    });

    test('claiming ten times pays once', () {
      var s = pass(start(established()), const Duration(minutes: 31));
      s = machine.claim(s).state!;
      final water = s.inventory.water;
      for (var i = 0; i < 10; i++) {
        s = machine.claim(s).state!;
      }
      expect(s.inventory.water, water);
    });

    test('a crash before the claim loses nothing: the reload claims it', () {
      // The state as it would have been persisted at the moment of the crash.
      final persisted = pass(start(established()), const Duration(minutes: 31));
      expect(persisted.session!.phase, FocusPhase.completed);

      // Relaunch from that save.
      final recovered = machine.claim(machine.evaluate(persisted));
      expect(recovered.ok, isTrue);
      expect(recovered.state!.session!.phase, FocusPhase.claimed);
      expect(
        recovered.state!.inventory.water,
        greaterThan(persisted.inventory.water),
      );
    });

    test('a crash after the claim does not pay again', () {
      var s = pass(start(established()), const Duration(minutes: 31));
      s = machine.claim(s).state!;
      final persisted = s; // what hit the disk

      // Relaunch: evaluate then claim, exactly as recovery does.
      final recovered = machine.claim(machine.evaluate(persisted));
      expect(recovered.state!.inventory.water, persisted.inventory.water);
      expect(recovered.state!.progression.xp, persisted.progression.xp);
    });

    test('the growth injection is applied once too', () {
      var s = pass(start(established()), const Duration(minutes: 31));
      s = machine.claim(s).state!;
      final growth = only(s).stage.index * 100 + only(s).growth.value;
      for (var i = 0; i < 5; i++) {
        s = machine.claim(s).state!;
      }
      expect(
        only(s).stage.index * 100 + only(s).growth.value,
        closeTo(growth, 1e-9),
      );
    });
  });

  group('Q6 — interruption', () {
    test('ending early pays for the time actually spent', () {
      var s = start(established(), minutes: 60);
      s = pass(s, const Duration(minutes: 20));
      s = machine.endEarly(s).state!;
      final out = machine.claim(s).outcome!;

      expect(out.actual, const Duration(minutes: 20));
      expect(
        out.growthPoints,
        greaterThan(0),
        reason: 'there is no fail state; time spent is time paid for',
      );
    });

    test('and pays less than seeing it through', () {
      final early = machine
          .claim(
            machine
                .endEarly(
                  pass(
                    start(established(), minutes: 60),
                    const Duration(minutes: 20),
                  ),
                )
                .state!,
          )
          .outcome!;
      final full = machine
          .claim(
            pass(
              start(established(), minutes: 60),
              const Duration(minutes: 61),
            ),
          )
          .outcome!;
      expect(early.growthPoints, lessThan(full.growthPoints));
    });
  });

  group('Q10 — the 60-second simulation grid', () {
    test('a claim lands on the grid', () {
      var s = pass(start(established()), const Duration(minutes: 31));
      s = machine.claim(s).state!;
      expect(s.simTime.isOnGrid, isTrue);
    });

    test('the world lives through the session before the reward lands', () {
      // Order matters: simulate first, then inject. Injecting into a world
      // that has not yet lived through the session would have the simulation
      // consume part of the reward.
      final s = start(established(water: 58), minutes: 60);
      final lived = pass(s, const Duration(minutes: 61));
      expect(
        only(lived).water.value,
        lessThan(58),
        reason: 'an hour of thirst happened during the session',
      );

      final claimed = machine.claim(lived).state!;
      expect(only(claimed).growth.value, greaterThan(only(lived).growth.value));
    });
  });

  group('streaks', () {
    test('a session on a new day extends the streak once', () {
      var s = established();
      for (var day = 0; day < 3; day++) {
        s = start(s.withSession(null), minutes: 10, id: 'd$day');
        s = machine.claim(pass(s, const Duration(minutes: 11))).state!;
        s = sim().run(state: s, to: SimTime((day + 1) * SimTime.dayMs)).state;
      }
      expect(s.progression.focusStreakDays, 3);
    });

    test('two sessions in one day do not double-count', () {
      var s = start(established(), minutes: 10, id: 'a');
      s = machine.claim(pass(s, const Duration(minutes: 11))).state!;
      final after1 = s.progression.focusStreakDays;
      s = machine.dismiss(s).state!;
      s = start(s, minutes: 10, id: 'b');
      s = machine.claim(pass(s, const Duration(minutes: 11))).state!;
      expect(s.progression.focusStreakDays, after1);
    });

    test('a shield covers one missed day, silently', () {
      var s = start(established(), minutes: 10, id: 'a');
      s = machine.claim(pass(s, const Duration(minutes: 11))).state!;
      expect(s.progression.streakShields, 1);

      // Skip a day.
      s = sim().run(state: s, to: SimTime(2 * SimTime.dayMs)).state;
      s = machine.dismiss(s).state!;
      s = start(s, minutes: 10, id: 'b');
      s = machine.claim(pass(s, const Duration(minutes: 11))).state!;

      expect(s.progression.focusStreakDays, 2, reason: 'streak continued');
      expect(s.progression.streakShields, 0, reason: 'the shield was spent');
    });
  });

  group('fatigue applies across sessions in a day', () {
    test('the third session of a day pays less than the first', () {
      var s = established();
      final paid = <int>[];
      for (var i = 0; i < 3; i++) {
        s = start(s.withSession(null), minutes: 30, id: 'f$i');
        final t = machine.claim(pass(s, const Duration(minutes: 31)));
        paid.add(t.outcome!.growthPoints);
        s = t.state!;
      }
      expect(
        paid[2],
        lessThan(paid[1]),
        reason: 'the third session of a day carries fatigue',
      );
      // The second pays slightly *more* than the first, not less: fatigue is
      // equal for both, and the first claim advanced the streak to one day,
      // which is worth +5%. Fatigue itself is pinned in economy_test.
      expect(paid[1], greaterThan(paid[0]));
      expect(paid[1] / paid[0], closeTo(1.05, 0.02));
    });
  });
}
