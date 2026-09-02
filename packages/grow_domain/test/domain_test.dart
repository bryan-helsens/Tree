import 'package:grow_domain/grow_domain.dart';
import 'package:test/test.dart';

void main() {
  group('Band', () {
    const oakWater = Band(min: 45, max: 70, tolLow: 30, tolHigh: 20);

    test('is 1.0 everywhere inside the ideal range', () {
      for (final x in [45.0, 50.0, 57.5, 70.0]) {
        expect(oakWater.comfort(x), 1.0);
      }
    });

    test('is gentle just outside and steep further out', () {
      final near = 1.0 - oakWater.comfort(75); // 5 above
      final far = 1.0 - oakWater.comfort(85); // 15 above
      expect(
        far / near,
        greaterThan(3.0),
        reason: 'the penalty must accelerate, or nothing teaches restraint',
      );
    });

    test('reaches exactly zero at the tolerance edge, and stays there', () {
      expect(oakWater.comfort(70 + 20), 0.0);
      expect(oakWater.comfort(45 - 30), 0.0);
      expect(oakWater.comfort(100), 0.0);
      expect(oakWater.comfort(0), 0.0);
    });

    test('is asymmetric — too wet costs more than equally too dry', () {
      expect(oakWater.comfort(70 + 15), lessThan(oakWater.comfort(45 - 15)));
    });

    test('reports the signed excursion for the UI warning', () {
      expect(oakWater.excursion(57), 0);
      expect(oakWater.excursion(80), 10);
      expect(oakWater.excursion(40), -5);
    });

    test('survives a degenerate band without dividing by zero', () {
      const point = Band(min: 50, max: 50, tolLow: 1, tolHigh: 1);
      expect(point.comfort(50), 1.0);
      expect(point.comfort(51), 0.0);
      expect(point.comfort(49), 0.0);
    });

    test('round-trips through JSON', () {
      final back = Band.fromJson(oakWater.toJson());
      expect(back.min, oakWater.min);
      expect(back.tolHigh, oakWater.tolHigh);
    });
  });

  group('Vital', () {
    test('clamps on construction', () {
      expect(Vital(150).value, 100);
      expect(Vital(-20).value, 0);
    });

    test('turns NaN into zero rather than propagating it', () {
      expect(Vital(double.nan).value, 0);
    });

    test('clamps through arithmetic', () {
      expect((Vital(95) + 20).value, 100);
      expect((Vital(5) - 20).value, 0);
    });
  });

  group('SimTime', () {
    test('floors to the 60-second grid', () {
      expect(const SimTime(59999).floorToStep.ms, 0);
      expect(const SimTime(60000).floorToStep.ms, 60000);
      expect(const SimTime(60001).floorToStep.ms, 60000);
    });

    test('hour and day indices are absolute, not relative', () {
      expect((SimTime.zero + const Duration(hours: 5)).hourIndex, 5);
      expect((SimTime.zero + const Duration(days: 3)).dayIndex, 3);
      expect((SimTime.zero + const Duration(hours: 26)).hourOfDay, 2.0);
    });

    test('grid alignment is detectable', () {
      expect(const SimTime(120000).isOnGrid, isTrue);
      expect(const SimTime(120001).isOnGrid, isFalse);
    });
  });

  group('Progression', () {
    test('matches the published XP curve', () {
      // docs/06 §6 indexes its table by *target* level, so the cost of
      // reaching level N is xpToNext(N - 1).
      expect(Progression.xpToNext(1), 90); // reach level 2
      expect(Progression.xpToNext(2), 246); // reach level 3
      expect(Progression.xpToNext(3), 443); // reach level 4
      expect(Progression.xpToNext(4), 672); // reach level 5
      expect(Progression.xpToNext(5), 928); // reach level 6
      expect(Progression.xpToNext(9), 2177); // reach level 10
    });

    test('cumulative XP to level 10 lands near the published 9,113', () {
      expect(Progression.cumulativeXpFor(10), closeTo(9113, 30));
    });

    test('a large XP grant cascades through several levels at once', () {
      const p = Progression.starting();
      final r = p.addXp(1000);
      expect(r.levelsGained, greaterThanOrEqualTo(3));
      expect(r.progression.xp, lessThan(r.progression.xpForNextLevel));
    });

    test('an absurd XP grant terminates instead of spinning', () {
      final r = const Progression.starting().addXp(1 << 40);
      expect(r.levelsGained, lessThanOrEqualTo(101));
    });

    test('the streak multiplier caps at +50%', () {
      expect(
        const Progression.starting()
            .copyWith(focusStreakDays: 999)
            .streakMultiplier,
        1.5,
      );
    });
  });

  group('Inventory', () {
    test('capacities follow the level formulas and stop at their ceilings', () {
      expect(Inventory.capacityForLevel(1), 15);
      expect(Inventory.capacityForLevel(4), 19);
      expect(Inventory.capacityForLevel(999), 45);
      expect(Inventory.nutrientCapacityForLevel(999), 20);
    });

    test('clamps to capacity and never goes negative', () {
      const inv = Inventory.starting();
      expect(inv.copyWith(water: 999).water, inv.waterCap);
      expect(inv.copyWith(water: -5).water, 0);
      expect(inv.copyWith(dew: 99).dew, Inventory.dewCap);
    });
  });

  group('HealthState', () {
    test('never relies on colour alone', () {
      for (final s in HealthState.values) {
        expect(s.glyph.trim(), isNotEmpty);
        expect(s.label.trim(), isNotEmpty);
      }
    });

    test('a snag is not alive but is still present', () {
      expect(HealthState.snag.isAlive, isFalse);
      expect(HealthState.healthy.isAlive, isTrue);
    });
  });

  group('GrowthStage', () {
    test('has a drink and attract weight for every stage', () {
      expect(GrowthStage.drinkFactor, hasLength(GrowthStage.values.length));
      expect(GrowthStage.attractWeight, hasLength(GrowthStage.values.length));
    });

    test('bigger trees drink more and attract more', () {
      expect(GrowthStage.mature.drink, greaterThan(GrowthStage.seed.drink));
      expect(
        GrowthStage.mature.attract,
        greaterThan(GrowthStage.sapling.attract),
      );
    });

    test('the final stage does not advance past itself', () {
      expect(GrowthStage.ancient.next, GrowthStage.ancient);
      expect(GrowthStage.ancient.isFinal, isTrue);
    });
  });
}
