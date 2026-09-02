import 'dart:math' as math;

import 'package:grow_domain/grow_domain.dart';
import 'package:grow_sim/grow_sim.dart';
import 'package:test/test.dart';

import 'support.dart';

/// The invariants the whole architecture leans on. Each maps to a numbered
/// property in docs/15-testing-strategy.md §2.
void main() {
  group('P1 composition — run(a→c) ≡ run(a→b) then run(b→c)', () {
    test('holds across 400 randomised window splits', () {
      final rnd = math.Random(20260902);
      for (var trial = 0; trial < 400; trial++) {
        final start = established(seed: rnd.nextInt(1 << 30));
        // Total windows from 10 minutes to 10 days.
        final totalMin = 10 + rnd.nextInt(14400);
        final splitMin = rnd.nextInt(totalMin + 1);

        final end = start.simTime + Duration(minutes: totalMin);
        final mid = start.simTime + Duration(minutes: splitMin);

        final oneShot = sim().run(state: start, to: end).state;
        final first = sim().run(state: start, to: mid).state;
        final chunked = sim().run(state: first, to: end).state;

        expectStatesEqual(
          oneShot,
          chunked,
          reason: 'trial $trial: $totalMin min split at $splitMin',
        );
      }
    });

    test('holds across the dormancy boundary specifically', () {
      // Dormancy keys off time-since-interaction, not window size, which is the
      // only formulation under which this passes.
      for (final splitHours in [1, 24, 71, 72, 73, 100, 200]) {
        final start = established(seed: 4242);
        final end = start.simTime + const Duration(days: 12);
        final mid = start.simTime + Duration(hours: splitHours);

        final oneShot = sim().run(state: start, to: end).state;
        final chunked = sim()
            .run(
              state: sim().run(state: start, to: mid).state,
              to: end,
            )
            .state;
        expectStatesEqual(oneShot, chunked, reason: 'split at ${splitHours}h');
      }
    });

    test('holds when split into 200 equal chunks', () {
      final start = established(seed: 77);
      final end = start.simTime + const Duration(days: 5);
      final oneShot = sim().run(state: start, to: end).state;

      var s = start;
      const chunks = 200;
      for (var i = 1; i <= chunks; i++) {
        s = sim()
            .run(
              state: s,
              to: start.simTime + Duration(minutes: 36 * i),
            )
            .state;
      }
      expectStatesEqual(oneShot, s, reason: '200-chunk replay');
    });
  });

  group('P2 determinism', () {
    test('same inputs produce identical output, repeatedly', () {
      final start = established(seed: 31337);
      final end = start.simTime + const Duration(days: 9);
      final a = sim().run(state: start, to: end);
      for (var i = 0; i < 5; i++) {
        expectStatesEqual(
          a.state,
          sim().run(state: start, to: end).state,
          reason: 'repeat $i',
        );
      }
      expect(
        a.journal.map((e) => e.message).toList(),
        sim().run(state: start, to: end).journal.map((e) => e.message).toList(),
      );
    });

    test('different world seeds diverge', () {
      final end = SimTime.zero + const Duration(days: 20);
      final a = sim().run(state: established(seed: 1), to: end).state;
      final b = sim().run(state: established(seed: 2), to: end).state;
      expect(only(a).water.value, isNot(closeTo(only(b).water.value, 1e-6)));
    });
  });

  group('P3 bounds — no vital ever escapes [0,100], no NaN', () {
    test('across 2000 randomised states and windows', () {
      final rnd = math.Random(5150);
      for (var i = 0; i < 2000; i++) {
        var s = established(
          seed: rnd.nextInt(1 << 30),
          species: rnd.nextBool() ? oak : birch,
          water: rnd.nextDouble() * 100,
          nutrition: rnd.nextDouble() * 100,
          health: rnd.nextDouble() * 100,
          stage: GrowthStage.values[rnd.nextInt(GrowthStage.values.length)],
        );
        s = sim()
            .run(
              state: s,
              to: s.simTime + Duration(hours: rnd.nextInt(900)),
            )
            .state;
        for (final t in s.trees) {
          for (final v in [t.health, t.water, t.nutrition, t.growth]) {
            expect(v.value.isFinite, isTrue, reason: '$t');
            expect(v.value, inInclusiveRange(0, 100), reason: '$t');
          }
          expect(t.criticalHours.isFinite, isTrue);
          expect(t.criticalHours, greaterThanOrEqualTo(0));
        }
      }
    });

    test('survives adversarial vitals at the extremes', () {
      for (final w in [0.0, 100.0]) {
        for (final n in [0.0, 100.0]) {
          for (final h in [0.0, 100.0]) {
            final s = sim().run(
              state: established(water: w, nutrition: n, health: h),
              to: SimTime.zero + const Duration(days: 30),
            );
            for (final t in s.state.trees) {
              expect(t.health.value.isFinite, isTrue);
              expect(t.water.value, inInclusiveRange(0, 100));
            }
          }
        }
      }
    });
  });

  group('P4 monotonicity', () {
    test('simTime never decreases and growth never reverses', () {
      var s = established(seed: 606);
      var lastAbs = 0.0;
      var lastTime = s.simTime.ms;
      for (var i = 0; i < 300; i++) {
        s = sim().run(state: s, to: s.simTime + const Duration(hours: 2)).state;
        expect(s.simTime.ms, greaterThanOrEqualTo(lastTime));
        lastTime = s.simTime.ms;
        final t = only(s);
        final abs = t.stage.index * 100.0 + t.growth.value;
        expect(
          abs,
          greaterThanOrEqualTo(lastAbs - 1e-9),
          reason: 'growth went backwards at iteration $i',
        );
        lastAbs = abs;
      }
    });

    test('a target in the past is a no-op, not negative progress', () {
      final s = sim()
          .run(state: established(), to: SimTime.zero + const Duration(days: 2))
          .state;
      final rewound = sim().run(state: s, to: SimTime.zero).state;
      expectStatesEqual(s, rewound, reason: 'rewind must not regress');
    });
  });

  group('P5 Charter C1 — absence alone can never kill a tree', () {
    test('365 days with zero player actions, both species', () {
      for (final species in [oak, birch]) {
        for (final seed in [1, 7, 99, 12345, 88888]) {
          final s = sim().run(
            state: established(seed: seed, species: species),
            to: SimTime.zero + const Duration(days: 365),
          );
          final t = only(s.state);
          expect(
            t.isAlive,
            isTrue,
            reason: '${species.raw} seed $seed died from absence',
          );
          expect(t.state, HealthState.dormant);
          expect(
            t.health.value,
            greaterThanOrEqualTo(15.0 - 1e-9),
            reason: 'dormancy floor breached: $t',
          );
        }
      }
    });

    test('even starting from near-zero health', () {
      final s = sim().run(
        state: established(health: 2, water: 3, nutrition: 3),
        to: SimTime.zero + const Duration(days: 400),
      );
      expect(only(s.state).isAlive, isTrue);
    });
  });

  group('P6 recoverability', () {
    test('a neglected tree returns to healthy within 48h of correct care', () {
      // Two weeks of neglect, then the player comes back and tends it.
      var s = sim()
          .run(
            state: established(seed: 24),
            to: SimTime.zero + const Duration(days: 14),
          )
          .state;
      expect(only(s).state, HealthState.dormant);

      s = s
          .touched(s.simTime)
          .copyWith(
            inventory: const Inventory.starting().copyWith(
              water: 10,
              nutrients: 4,
            ),
          );
      final actions = Actions(content);
      // Five affordable actions, the budget the property allows.
      for (var i = 0; i < 3; i++) {
        final r = actions.water(s, only(s).id);
        if (r.ok) s = r.state!;
      }
      for (var i = 0; i < 2; i++) {
        final r = actions.feed(s, only(s).id);
        if (r.ok) s = r.state!;
      }
      s = sim().run(state: s, to: s.simTime + const Duration(hours: 48)).state;

      expect(
        only(s).health.value,
        greaterThanOrEqualTo(70.0),
        reason: 'not recovered: ${only(s)}',
      );
      expect(only(s).state, isIn([HealthState.healthy, HealthState.thriving]));
    });
  });

  group('P7 Charter C5 — there is always a meaningful action', () {
    test('dew guarantees water is available after any absence', () {
      for (final hours in [3, 6, 24, 72, 240, 2400]) {
        final s = sim()
            .run(
              state: newGame().copyWith(
                inventory: const Inventory.starting().copyWith(water: 0),
              ),
              to: SimTime.zero + Duration(hours: hours),
            )
            .state;
        expect(
          s.inventory.totalWaterAvailable,
          greaterThan(0),
          reason: 'no action available after ${hours}h',
        );
      }
    });
  });

  group('P8 clock safety', () {
    test('replaying the same interval twice grants no extra dew', () {
      final target = SimTime.zero + const Duration(days: 1);
      final once = sim().run(state: newGame(), to: target).state;
      final twice = sim().run(state: once, to: target).state;
      expect(twice.inventory.dew, once.inventory.dew);
    });

    test('dew is capped regardless of how long the absence was', () {
      final s = sim()
          .run(state: newGame(), to: SimTime.zero + const Duration(days: 500))
          .state;
      expect(s.inventory.dew, Inventory.dewCap);
    });
  });
}
