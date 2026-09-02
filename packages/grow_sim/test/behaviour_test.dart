import 'package:grow_domain/grow_domain.dart';
import 'package:grow_sim/grow_sim.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Tests that the *design* works, not merely that the arithmetic is sound.
/// Each maps to a stated intent in the brief or the design charter.
void main() {
  group('overwatering', () {
    test(
      'is worse than the equivalent underwatering (asymmetric tolerance)',
      () {
        final species = content[oak];
        // 25 points outside the band in each direction.
        final dry = species.water.comfort(species.water.min - 25);
        final wet = species.water.comfort(species.water.max + 25);
        expect(
          wet,
          lessThan(dry),
          reason: 'roots should suffocate faster than leaves wilt',
        );
      },
    );

    test('stalls growth — that is the real cost, not a health crash', () {
      // A single mistake must never tank health: that would break the
      // "trees do not die easily" guarantee. What it costs is time.
      final dry = simUnder(WeatherKind.sunny);
      const window = Duration(hours: 12);

      final drowned = dry
          .run(
            state: established(water: 96, nutrition: 52, seed: 8),
            to: SimTime.zero + window,
          )
          .state;
      final tended = dry
          .run(
            state: established(water: 60, nutrition: 52, seed: 8),
            to: SimTime.zero + window,
          )
          .state;

      expect(
        only(drowned).growth.value,
        lessThan(only(tended).growth.value * 0.5),
        reason: 'saturated soil should visibly cost progress',
      );
      expect(
        only(drowned).state,
        isNot(HealthState.stressed),
        reason: 'one mistake must never reach a warning state',
      );
      expect(only(drowned).isAlive, isTrue);
    });

    test('recovers on its own once the player stops watering', () {
      final dry = simUnder(WeatherKind.sunny);
      var s = established(water: 96, nutrition: 52, seed: 8);
      s = dry.run(state: s, to: s.simTime + const Duration(hours: 30)).state;
      s = s.touched(s.simTime);
      s = dry.run(state: s, to: s.simTime + const Duration(hours: 18)).state;

      expect(only(s).health.value, greaterThan(85));
      expect(
        only(s).water.value,
        lessThanOrEqualTo(content[oak].water.max),
        reason: 'the soil should have drained back out of saturation',
      );
      expect(only(s).state, isIn([HealthState.healthy, HealthState.thriving]));
    });

    test(
      'sustained saturation — the player who keeps watering — does hurt',
      () {
        // The over-attentive player: tops the tree up every time they open the
        // app, using the real action API rather than poking the vitals.
        final dry = simUnder(WeatherKind.sunny);
        final actions = Actions(content);
        var s = established(water: 80, nutrition: 52, seed: 8).copyWith(
          inventory: const Inventory.starting().copyWith(
            waterCap: 99,
            water: 99,
            nutrientCap: 9,
          ),
        );
        for (var i = 0; i < 32; i++) {
          final r = actions.water(s, only(s).id);
          if (r.ok) s = r.state!;
          s = dry.run(state: s, to: s.simTime + const Duration(hours: 3)).state;
        }
        expect(
          only(s).health.value,
          lessThan(60),
          reason: 'persistent overwatering should genuinely degrade a tree',
        );
        expect(only(s).state.needsAttention, isTrue);
        expect(only(s).isAlive, isTrue, reason: 'but still not kill it');
      },
    );

    test('leaches nutrients — over-caring in one dimension costs another', () {
      final wet = sim()
          .run(
            state: established(water: 95, nutrition: 60),
            to: SimTime.zero + const Duration(hours: 24),
          )
          .state;
      final normal = sim()
          .run(
            state: established(water: 60, nutrition: 60),
            to: SimTime.zero + const Duration(hours: 24),
          )
          .state;
      expect(
        only(wet).nutrition.value,
        lessThan(only(normal).nutrition.value),
        reason: 'waterlogged soil should wash nutrients out',
      );
    });

    test('raises the chance of fungus', () {
      var fungusCount = 0;
      for (var seed = 0; seed < 60; seed++) {
        final s = sim()
            .run(
              state: established(seed: seed, water: 95),
              to: SimTime.zero + const Duration(hours: 48),
            )
            .state;
        if (only(s).has(AfflictionKind.fungus)) fungusCount++;
      }
      expect(
        fungusCount,
        greaterThan(0),
        reason: 'saturated soil should sometimes produce fungus',
      );
    });
  });

  group('overfeeding', () {
    test('past the margin produces nutrient burn, deterministically', () {
      final species = content[oak];
      final over = species.nutrition.max + 25;
      final s = sim()
          .run(
            state: established(nutrition: over),
            to: SimTime.zero + const Duration(hours: 2),
          )
          .state;
      expect(
        only(s).has(AfflictionKind.nutrientBurn),
        isTrue,
        reason: 'the cause must always be legible, so this is not a dice roll',
      );
    });

    test('inside the band produces no burn at all', () {
      final species = content[oak];
      final s = sim()
          .run(
            state: established(nutrition: species.nutrition.max),
            to: SimTime.zero + const Duration(hours: 24),
          )
          .state;
      expect(only(s).has(AfflictionKind.nutrientBurn), isFalse);
    });

    test('feeding a tree already at the top of its band is a real mistake', () {
      final actions = Actions(content);
      final species = content[oak];
      final s = established(nutrition: species.nutrition.max - 2);
      final preview = actions.previewFeed(only(s));
      expect(
        preview.leavesBand,
        isTrue,
        reason: 'the UI must be able to warn before the player commits',
      );
      expect(preview.to, greaterThan(species.nutrition.max));
    });
  });

  group('care quality drives growth', () {
    test('excellent care grows roughly twice as fast as mediocre care', () {
      // Same sky for both, so the only variable is how well they were tended.
      final sky = simUnder(WeatherKind.cloudy);
      final good = sky
          .run(
            state: established(water: 57, nutrition: 52, health: 95),
            to: SimTime.zero + const Duration(hours: 20),
          )
          .state;
      // Just outside both bands: the "not paying attention" player.
      final poor = sky
          .run(
            state: established(water: 33, nutrition: 26, health: 95),
            to: SimTime.zero + const Duration(hours: 20),
          )
          .state;

      final ratio = only(good).growth.value / only(poor).growth.value;
      expect(
        ratio,
        greaterThan(1.6),
        reason:
            'optimising should be visibly worth it (got ${ratio.toStringAsFixed(2)}x)',
      );
      expect(
        ratio,
        lessThan(6.0),
        reason: 'but a casual player must still make progress',
      );
    });

    test('growth halts below the health gate but never reverses', () {
      final s = sim()
          .run(
            state: established(health: 10, water: 5, nutrition: 5),
            to: SimTime.zero + const Duration(hours: 12),
          )
          .state;
      expect(only(s).growth.value, lessThan(1.0));
      expect(only(s).growth.value, greaterThanOrEqualTo(0));
    });

    test('a seed reaches sprout inside the first session', () {
      // The onboarding beat sheet depends on this: stage 1 → 2 in ~20 minutes.
      final s = sim()
          .run(state: newGame(), to: SimTime.zero + const Duration(minutes: 25))
          .state;
      expect(
        only(s).stage.index,
        greaterThanOrEqualTo(GrowthStage.sprout.index),
        reason: 'first payoff must land inside the first session',
      );
    });
  });

  group('death is hard to reach', () {
    test('never happens without sightings and a delivered notification', () {
      // Perfectly lethal conditions, a full year, but the player never saw it.
      final s = sim()
          .run(
            state: established(
              health: 1,
              water: 0,
              nutrition: 0,
            ).touched(SimTime.zero),
            to: SimTime.zero + const Duration(days: 365),
          )
          .state;
      expect(only(s).isAlive, isTrue);
    });

    test('happens only after all three gates are satisfied', () {
      var s = established(health: 5, water: 2, nutrition: 2);
      // The player has seen it critical twice and been notified.
      s = s.copyWith(
        trees: [
          only(s).copyWith(criticalSightings: 2, careNotificationSent: true),
        ],
      );

      // Keep the player "present" so dormancy never engages, and let the
      // critical clock run past its threshold.
      for (var day = 0; day < 12; day++) {
        s = s.touched(s.simTime);
        s = sim().run(state: s, to: s.simTime + const Duration(days: 1)).state;
      }
      expect(
        only(s).isSnag,
        isTrue,
        reason: 'sustained, witnessed, notified neglect should eventually end',
      );
    });

    test('a snag is not deletion — it stays in the forest', () {
      var s = established(health: 5, water: 2, nutrition: 2).copyWith(
        trees: [
          established().trees.first.copyWith(
            health: Vital(5),
            water: Vital(2),
            nutrition: Vital(2),
            criticalSightings: 2,
            careNotificationSent: true,
          ),
        ],
      );
      for (var day = 0; day < 12; day++) {
        s = s.touched(s.simTime);
        s = sim().run(state: s, to: s.simTime + const Duration(days: 1)).state;
      }
      expect(s.trees, hasLength(1));
      expect(only(s).state, HealthState.snag);
      expect(only(s).diedAt, isNotNull);
    });

    test('recovery forgives the critical clock at double rate', () {
      var s = established(health: 8, water: 3, nutrition: 3);
      s = s.touched(s.simTime);
      s = sim().run(state: s, to: s.simTime + const Duration(hours: 24)).state;
      final accrued = only(s).criticalHours;
      expect(accrued, greaterThan(0));

      // Restore it and let it recover. The tree has to climb back out of the
      // critical band first, so forgiveness starts a few hours in.
      s = s
          .copyWith(
            trees: [only(s).copyWith(water: Vital(58), nutrition: Vital(52))],
          )
          .touched(s.simTime);
      s = sim().run(state: s, to: s.simTime + const Duration(hours: 24)).state;
      expect(
        only(s).criticalHours,
        0,
        reason: 'a day of good care should clear the death clock entirely',
      );
    });
  });

  group('species behave differently', () {
    test('birch drinks more than oak under identical conditions', () {
      final end = SimTime.zero + const Duration(hours: 24);
      final o = sim()
          .run(
            state: established(species: oak, seed: 5),
            to: end,
          )
          .state;
      final b = sim()
          .run(
            state: established(species: birch, seed: 5),
            to: end,
          )
          .state;
      expect(only(b).water.value, lessThan(only(o).water.value));
    });

    test('birch grows faster when both are well cared for', () {
      final end = SimTime.zero + const Duration(hours: 12);
      final o = sim()
          .run(
            state: established(species: oak, seed: 5, water: 60),
            to: end,
          )
          .state;
      final b = sim()
          .run(
            state: established(species: birch, seed: 5, water: 62),
            to: end,
          )
          .state;
      expect(only(b).growth.value, greaterThan(only(o).growth.value));
    });

    test('their ideal bands genuinely differ, so care must be learned', () {
      expect(content[oak].water.min, isNot(content[birch].water.min));
      expect(content[oak].nutrition.max, isNot(content[birch].nutrition.max));
      // A nutrition level that is fine for an oak burns a birch.
      final level = content[oak].nutrition.max + 10;
      expect(
        content[oak].nutrition.comfort(level),
        greaterThan(content[birch].nutrition.comfort(level)),
      );
    });
  });

  group('weather', () {
    test('is forecastable — the same day always returns the same weather', () {
      final oracle = WeatherOracle(
        worldSeed: const Seed(4242),
        content: content,
      );
      for (var d = 0; d < 200; d++) {
        expect(oracle.weatherOn(d), oracle.weatherOn(d));
      }
    });

    test('is autocorrelated rather than flipping every day', () {
      final oracle = WeatherOracle(worldSeed: const Seed(11), content: content);
      var changes = 0;
      for (var d = 1; d < 400; d++) {
        if (oracle.weatherOn(d) != oracle.weatherOn(d - 1)) changes++;
      }
      expect(
        changes,
        lessThan(260),
        reason: 'weather should persist across days, not flip randomly',
      );
      expect(changes, greaterThan(20), reason: 'but it should still change');
    });

    test('rain adds moisture — free water, and the overwatering trap', () {
      final oracle = WeatherOracle(worldSeed: const Seed(3), content: content);
      final rainyDay = List.generate(
        400,
        (i) => i,
      ).firstWhere((d) => oracle.weatherOn(d).isWet);
      final from = SimTime(rainyDay * SimTime.dayMs);
      final s = established(
        seed: 3,
        water: 50,
      ).copyWith(simTime: from).touched(from);
      final after = sim()
          .run(state: s, to: from + const Duration(hours: 12))
          .state;
      expect(
        only(after).water.value,
        greaterThan(46),
        reason: 'rain should meaningfully offset consumption',
      );
    });

    test('the MVP ships only the weather the renderer can draw', () {
      expect(content.weatherTable.keys.toSet(), {
        WeatherKind.sunny,
        WeatherKind.cloudy,
        WeatherKind.rain,
      });
    });
  });

  group('actions', () {
    test('water spends dew before stored water', () {
      final actions = Actions(content);
      final s = established().copyWith(
        inventory: const Inventory.starting().copyWith(water: 5, dew: 2),
      );
      final r = actions.water(s, only(s).id);
      expect(r.ok, isTrue);
      expect(r.state!.inventory.dew, 1);
      expect(r.state!.inventory.water, 5, reason: 'capped dew would be wasted');
    });

    test('fail cleanly with an explanation when resources run out', () {
      final actions = Actions(content);
      final s = established().copyWith(
        inventory: const Inventory.starting().copyWith(water: 0, dew: 0),
      );
      final r = actions.water(s, only(s).id);
      expect(r.ok, isFalse);
      expect(r.error, ActionError.noWater);
      expect(r.error!.message, isNotEmpty);
    });

    test('preview reports entering the band as well as leaving it', () {
      final actions = Actions(content);
      final dry = established(water: 40);
      expect(actions.previewWater(only(dry)).enters, isTrue);
      expect(actions.previewWater(only(dry)).leavesBand, isFalse);

      final wet = established(water: 68);
      expect(actions.previewWater(only(wet)).leavesBand, isTrue);
    });

    test('a snag cannot be watered, and says why', () {
      final actions = Actions(content);
      final s = established().copyWith(
        trees: [established().trees.first.copyWith(state: HealthState.snag)],
      );
      final r = actions.water(s, only(s).id);
      expect(r.error, ActionError.treeIsSnag);
    });
  });

  group('health states', () {
    test('use hysteresis so the label does not flicker at a boundary', () {
      // Sitting just under the "healthy" entry threshold should not flip a
      // tree that is already healthy.
      final stillHealthy = HealthThresholds.resolve(
        health: 66,
        comfort: 0.8,
        previous: HealthState.healthy,
      );
      expect(stillHealthy, HealthState.healthy);

      final notYetHealthy = HealthThresholds.resolve(
        health: 66,
        comfort: 0.8,
        previous: HealthState.stressed,
      );
      expect(notYetHealthy, HealthState.stressed);
    });

    test('every state carries a glyph and a word, not just a colour', () {
      for (final s in HealthState.values) {
        expect(s.glyph, isNotEmpty);
        expect(s.label, isNotEmpty);
      }
    });
  });
}
