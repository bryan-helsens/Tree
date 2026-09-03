import 'package:grow_domain/grow_domain.dart';
import 'package:grow_sim/grow_sim.dart';
import 'package:test/test.dart';

import 'support.dart';

/// What happens when the clock moves unexpectedly (docs/22 §11).
///
/// Every branch is exercised without waiting, rebooting, or changing a
/// device's date, because the guard reads no clock — it is handed readings.
void main() {
  const guard = ClockGuard();

  ClockReading at(int wallMs, int monotonicMs, [String boot = 'boot-1']) =>
      ClockReading(wallMs: wallMs, monotonicMs: monotonicMs, bootId: boot);

  ClockMeta meta(
    int wallMs,
    int monotonicMs, {
    String boot = 'boot-1',
    int high = 0,
  }) => ClockMeta(
    lastWallMs: wallMs,
    lastMonotonicMs: monotonicMs,
    bootId: boot,
    simTimeHighMs: high,
  );

  const hour = 3600 * 1000;

  group('the ordinary case', () {
    test('both clocks agree, so the interval is credited in full', () {
      final e = guard.elapsed(meta(1000, 500), at(1000 + hour, 500 + hour));
      expect(e.ms, hour);
      expect(e.anomaly, ClockAnomaly.none);
    });

    test('a fresh save credits nothing and starts the record', () {
      expect(guard.elapsed(const ClockMeta.initial(), at(9999, 9999)).ms, 0);
    });
  });

  group('the clock moves backwards', () {
    test('progress is zero, never negative', () {
      final e = guard.elapsed(
        meta(10 * hour, 10 * hour),
        at(2 * hour, 11 * hour),
      );
      expect(e.ms, 0);
      expect(e.anomaly, ClockAnomaly.rewind);
    });

    test('and a tree does not lose the day it already lived', () {
      // simTime is monotonic: the target can never fall below where it was.
      final s = established().copyWith(
        clock: meta(10 * hour, 10 * hour, high: 5 * hour),
      );
      final r = guard.advance(s, at(2 * hour, 11 * hour));
      expect(r.target.ms, greaterThanOrEqualTo(s.simTime.ms));
    });
  });

  group('the clock is pushed forward', () {
    test('the monotonic clock caps the credit within one boot', () {
      // Wall clock jumped a day; the device was only awake an hour.
      final e = guard.elapsed(meta(0, 0), at(24 * hour, hour));
      expect(e.ms, hour, reason: 'the smaller of the two is the honest one');
      expect(e.anomaly, ClockAnomaly.forwardJump);
    });

    test('so a session cannot be finished by changing the date', () {
      final s = established().copyWith(clock: meta(0, 0));
      final r = guard.advance(s, at(365 * 24 * hour, 60 * 1000));
      expect(r.target.ms - s.simTime.ms, lessThanOrEqualTo(60 * 1000));
    });
  });

  group('after a reboot', () {
    test(
      'the monotonic clock cannot corroborate, so the wall clock is capped',
      () {
        final e = guard.elapsed(
          meta(0, 50 * hour, boot: 'boot-1'),
          at(200 * hour, 30 * 1000, 'boot-2'),
        );
        expect(e.anomaly, ClockAnomaly.reboot);
        expect(e.ms, const ClockGuard().maxResumeMs);
      },
    );

    test('an ordinary overnight reboot is credited normally', () {
      final e = guard.elapsed(
        meta(0, 50 * hour, boot: 'boot-1'),
        at(8 * hour, 30 * 1000, 'boot-2'),
      );
      expect(e.ms, 8 * hour);
    });
  });

  group('a restored older save', () {
    test('cannot re-earn time the game already lived through', () {
      // The high-water mark outlives the save file it came from.
      final rolledBack = established().copyWith(
        simTime: SimTime(2 * hour),
        clock: meta(0, 0, high: 40 * hour),
      );
      final r = guard.advance(rolledBack, at(hour, hour));
      expect(r.target.ms, greaterThanOrEqualTo(40 * hour));
      expect(r.meta.simTimeHighMs, greaterThanOrEqualTo(40 * hour));
    });
  });

  group('bookkeeping', () {
    test('the target always lands on the simulation grid', () {
      for (final ms in [1, 59999, 60001, 123456, 7654321]) {
        final s = established().copyWith(clock: meta(0, 0));
        expect(guard.advance(s, at(ms, ms)).target.isOnGrid, isTrue);
      }
    });

    test('anomalies are counted but never acted on punitively', () {
      final s = established().copyWith(clock: meta(10 * hour, 10 * hour));
      final r = guard.advance(s, at(0, 11 * hour));
      expect(r.meta.anomalies, 1);
      // Counting is all that happens. Nothing is taken away.
      expect(r.target.ms, greaterThanOrEqualTo(s.simTime.ms));
    });

    test('the high-water mark only ever rises', () {
      var s = established().copyWith(clock: meta(0, 0, high: 100));
      for (final step in [hour, 2 * hour, 0, hour]) {
        final r = guard.advance(s, at(step, step));
        expect(
          r.meta.simTimeHighMs,
          greaterThanOrEqualTo(s.clock.simTimeHighMs),
        );
        s = s.copyWith(simTime: r.target, clock: r.meta);
      }
    });

    test('anchoring records the clocks without crediting time', () {
      final s = established();
      final anchored = guard.anchor(s, at(5000, 900));
      expect(anchored.lastWallMs, 5000);
      expect(anchored.bootId, 'boot-1');
      expect(anchored.simTimeHighMs, greaterThanOrEqualTo(s.simTime.ms));
    });
  });

  group('a session across a hostile clock', () {
    test('cannot be completed early by any clock movement', () {
      final machine = FocusMachine(content: content);
      var s = machine
          .start(
            established(),
            planned: const Duration(minutes: 30),
            id: 'x',
            wallMs: 0,
          )
          .state!
          .copyWith(clock: meta(0, 0));

      // Try to jump a year forward. The monotonic clock says one minute.
      final r = guard.advance(s, at(365 * 24 * hour, 60 * 1000));
      s = machine.evaluate(s.copyWith(simTime: r.target, clock: r.meta));
      expect(
        s.session!.phase,
        FocusPhase.running,
        reason: 'a minute of real time is a minute of session',
      );
    });
  });
}
