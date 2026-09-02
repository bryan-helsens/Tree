import 'package:grow_sim/grow_sim.dart';
import 'package:test/test.dart';

void main() {
  const economy = FocusEconomy();

  FocusYield y(int minutes, {int index = 0, int streak = 0, int today = 0}) =>
      economy.yieldFor(
        minutes: minutes,
        sessionIndexToday: index,
        streakDays: streak,
        gpAlreadyEarnedToday: today,
      );

  group('the published reward table', () {
    // These are the numbers shown to the player in docs/06 §2. If the formula
    // changes, the table changes, and this test is how we find out.
    const expected = {
      10: (gp: 63, water: 1, nutrients: 0),
      20: (gp: 110, water: 2, nutrients: 0),
      30: (gp: 152, water: 3, nutrients: 0),
      45: (gp: 210, water: 4, nutrients: 1),
      60: (gp: 265, water: 5, nutrients: 1),
      120: (gp: 461, water: 10, nutrients: 2),
      // Note: `nutrients` is the base conversion. The Deep Focus bonus is
      // reported separately so the UI can celebrate it on its own line.
    };

    for (final e in expected.entries) {
      test('${e.key} min pays ${e.value.gp} gp', () {
        final r = y(e.key);
        expect(r.growthPoints, e.value.gp);
        expect(r.water, e.value.water);
        expect(r.nutrients, e.value.nutrients);
      });
    }
  });

  group('diminishing returns', () {
    test('the marginal minute is worth less as a session lengthens', () {
      var last = double.infinity;
      for (final m in [10, 20, 30, 45, 60, 90, 120]) {
        final perMinute = y(m).growthPoints / m;
        expect(perMinute, lessThan(last), reason: '$m min broke the curve');
        last = perMinute;
      }
    });

    test('minute 120 is worth roughly 60% of minute 10', () {
      final ratio = (y(120).growthPoints / 120) / (y(10).growthPoints / 10);
      expect(ratio, closeTo(0.60, 0.05));
    });

    test('two 30s beat one 60, so the equilibrium is medium sessions', () {
      final two = y(30, index: 0).water + y(30, index: 1).water;
      expect(two, greaterThan(y(60, index: 0).water));
    });

    test('but a long session is not punished — it wins on quality', () {
      expect(y(60).deepFocusBonus, isTrue);
      expect(y(30).deepFocusBonus, isFalse);
      expect(y(45).totalNutrients, greaterThan(y(30).totalNutrients));
      expect(y(45).bonusNutrients, 1);
      expect(y(30).bonusNutrients, 0);
    });

    test('the first two sessions of a day are both full weight', () {
      expect(FocusEconomy.fatigue(0), 1.0);
      expect(FocusEconomy.fatigue(1), 1.0);
      expect(FocusEconomy.fatigue(2), lessThan(1.0));
    });

    test('fatigue never reaches zero', () {
      for (var i = 0; i < 50; i++) {
        expect(FocusEconomy.fatigue(i), greaterThanOrEqualTo(0.30));
      }
    });
  });

  group('integrity — Charter C2, no fail state', () {
    test('never returns zero, however much the phone was used', () {
      for (final pct in [0.0, 0.25, 0.5, 0.9, 1.0]) {
        final i = FocusEconomy.integrityFrom(
          window: const Duration(minutes: 60),
          screenOn: Duration(minutes: (60 * pct).round()),
        );
        expect(i, greaterThanOrEqualTo(0.35));
        expect(i, lessThanOrEqualTo(1.0));
      }
    });

    test('a brief glance at the clock costs nothing', () {
      final i = FocusEconomy.integrityFrom(
        window: const Duration(minutes: 60),
        screenOn: const Duration(minutes: 2),
      );
      expect(i, 1.0);
    });

    test('heavy use reduces but does not eliminate the reward', () {
      final r = economy.yieldFor(
        minutes: 60,
        sessionIndexToday: 0,
        streakDays: 0,
        gpAlreadyEarnedToday: 0,
        integrity: 0.35,
      );
      expect(r.growthPoints, greaterThan(0));
      expect(r.water, greaterThan(0));
    });

    test('an unavailable measurement means full reward, not a penalty', () {
      // The permission-free default must not be the punished path.
      expect(y(30).integrity, 1.0);
    });
  });

  group('streaks', () {
    test('cap at +50% so they never become coercive', () {
      expect(y(30, streak: 100).growthPoints, y(30, streak: 10).growthPoints);
      expect(
        y(30, streak: 10).growthPoints / y(30, streak: 0).growthPoints,
        closeTo(1.5, 0.02),
      );
    });
  });

  group('daily soft cap', () {
    test('does not bite at realistic volumes', () {
      // Three 45-minute sessions is a heavy but plausible day.
      var today = 0;
      for (var i = 0; i < 3; i++) {
        final r = y(45, index: i, today: today);
        today += r.growthPoints;
      }
      expect(today, lessThan(FocusEconomy().dailySoftCapGp));
    });

    test('bounds the ceiling at implausible volumes', () {
      final over = y(60, index: 0, today: 1200);
      final under = y(60, index: 0, today: 0);
      expect(over.growthPoints, lessThan(under.growthPoints * 0.3));
    });
  });

  group('session bounds', () {
    test('clamps absurd durations rather than trusting them', () {
      expect(y(100000).minutes, 120);
      expect(y(0).minutes, 5);
      expect(y(-50).growthPoints, greaterThan(0));
    });
  });
}
