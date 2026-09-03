import 'package:grow_domain/grow_domain.dart';
import 'package:grow_sim/grow_sim.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Appearance must be a *consequence* of simulation, never a hand-set value.
/// These tests pin the causal link.
void main() {
  final projector = WorldProjector(content: content);

  FoliageState foliageOf(GameState s) =>
      projector.project(s).trees.first.foliage;

  group('thirst drives droop', () {
    test('a tree inside its band does not droop', () {
      expect(
        foliageOf(established(water: 58, health: 95)).droop,
        lessThan(0.12),
      );
    });

    test('droop rises as moisture falls below the band', () {
      var last = -1.0;
      for (final w in [45.0, 38.0, 30.0, 22.0, 15.0]) {
        final d = foliageOf(established(water: w, health: 95)).droop;
        expect(d, greaterThan(last), reason: 'no response at water $w');
        last = d;
      }
    });

    test('it saturates at the band tolerance rather than running away', () {
      expect(foliageOf(established(water: 0, health: 95)).droop, 1.0);
    });

    test('a sick tree sags even when freshly watered', () {
      // Turgor is not only about water: an unhealthy tree should look unwell
      // immediately after care, or watering would appear to fix everything.
      expect(
        foliageOf(established(water: 58, health: 20)).droop,
        greaterThan(0.35),
      );
    });
  });

  group('nutrition drives colour', () {
    test('hunger pales, excess scorches, and they do not overlap', () {
      final hungry = foliageOf(established(nutrition: 10));
      expect(hungry.pallor, greaterThan(0.5));
      expect(hungry.scorch, 0);

      final overfed = foliageOf(established(nutrition: 95));
      expect(overfed.scorch, greaterThan(0.5));
      expect(overfed.pallor, 0);
    });

    test('a nutrient burn keeps showing after the excess is corrected', () {
      var s = established(nutrition: 95);
      s = sim().run(state: s, to: s.simTime + const Duration(hours: 3)).state;
      expect(only(s).has(AfflictionKind.nutrientBurn), isTrue);

      // Bring nutrition back into the band; the damage is still visible.
      s = s.copyWith(trees: [only(s).copyWith(nutrition: Vital(52))]);
      expect(
        foliageOf(s).scorch,
        greaterThan(0.2),
        reason: 'scorched leaves do not un-scorch the moment you stop',
      );
    });

    test(
      'band tolerance is per species, so the same value reads differently',
      () {
        // Birch has a tighter nutrient ceiling than oak. At one level the oak is
        // fine and the birch is burning — with no per-species art or branch.
        const level = 74.0;
        final oakScorch = foliageOf(
          established(species: oak, nutrition: level),
        ).scorch;
        final birchScorch = foliageOf(
          established(species: birch, nutrition: level),
        ).scorch;
        expect(birchScorch, greaterThan(oakScorch));
      },
    );
  });

  group('saturation drives wetness', () {
    test('waterlogged soil reads wet', () {
      expect(foliageOf(established(water: 95)).wetness, greaterThan(0.5));
    });

    test('rain darkens the ground even for a well-watered tree', () {
      final oracle = WeatherOracle(worldSeed: const Seed(3), content: content);
      final wetHour = List.generate(
        2000,
        (i) => i,
      ).firstWhere((h) => oracle.rainRateAt(SimTime(h * SimTime.hourMs)) > 0);
      final at = SimTime(wetHour * SimTime.hourMs);
      final s = established(seed: 3, water: 58).copyWith(simTime: at);
      expect(foliageOf(s).wetness, greaterThan(0.3));
    });
  });

  group('sparkle is earned', () {
    test('only a thriving tree sparkles', () {
      var s = established(water: 58, nutrition: 52, health: 99);
      s = s.copyWith(trees: [only(s).copyWith(state: HealthState.thriving)]);
      expect(foliageOf(s).sparkle, greaterThan(0));

      final merelyHealthy = established(water: 58, nutrition: 52, health: 75);
      expect(foliageOf(merelyHealthy).sparkle, 0);
    });
  });

  group('growth fraction', () {
    test('spans the whole stage ladder monotonically', () {
      var last = -1.0;
      for (final stage in GrowthStage.values) {
        for (final within in [0.0, 50.0, 99.0]) {
          final s = established(stage: stage).copyWith(
            trees: [
              established().trees.first.copyWith(
                stage: stage,
                growth: Vital(within),
              ),
            ],
          );
          final f = WorldProjector.growthFraction(only(s));
          expect(f, inInclusiveRange(0, 1));
          expect(f, greaterThanOrEqualTo(last));
          last = f;
        }
      }
    });

    test('a seed is near zero and an ancient is exactly one', () {
      final seed = established(stage: GrowthStage.seed).copyWith(
        trees: [
          established().trees.first.copyWith(
            stage: GrowthStage.seed,
            growth: Vital.zero,
          ),
        ],
      );
      expect(WorldProjector.growthFraction(only(seed)), 0);

      final old = established().copyWith(
        trees: [established().trees.first.copyWith(stage: GrowthStage.ancient)],
      );
      expect(WorldProjector.growthFraction(only(old)), 1.0);
    });
  });

  group('a snag reads as deadwood', () {
    test('bare, and not merely unhealthy', () {
      final s = established().copyWith(
        trees: [established().trees.first.copyWith(state: HealthState.snag)],
      );
      final f = foliageOf(s);
      expect(f.bareness, 1.0);
      expect(f.sparkle, 0);
    });
  });

  group('accessibility description', () {
    test('names the species, stage, state and both bands', () {
      final s = established(water: 62, nutrition: 54);
      final d = projector.project(s).trees.first.detail;
      expect(d, contains('Pedunculate Oak'));
      expect(d, contains('sapling'));
      expect(d, contains('Water 62'));
      expect(d, contains('ideal 45 to 70'));
      expect(d, contains('Nutrition 54'));
    });

    test('names the limiting factor when a tree needs help', () {
      // Reported state comes from the simulator's hysteresis, not from health
      // directly, so let the simulation actually put the tree in trouble.
      var s = established(water: 8, nutrition: 52, health: 30);
      s = sim().run(state: s, to: s.simTime + const Duration(hours: 6)).state;
      expect(
        only(s).state.needsAttention,
        isTrue,
        reason: 'test setup: the tree should be in trouble by now',
      );
      expect(
        projector.project(s).trees.first.detail,
        contains('Most limited by water'),
      );
    });

    test('stays quiet about causes when the tree is fine', () {
      final d = projector
          .project(established(water: 58, nutrition: 52, health: 95))
          .trees
          .first
          .detail;
      expect(d, isNot(contains('Most limited by')));
    });

    test('mentions every affliction the tree carries', () {
      var s = established(nutrition: 95);
      s = sim().run(state: s, to: s.simTime + const Duration(hours: 3)).state;
      expect(
        projector.project(s).trees.first.detail,
        contains('Nutrient burn'),
      );
    });
  });

  group('smoothing', () {
    test('condition changes ease in rather than snapping', () {
      const from = FoliageState();
      const to = FoliageState(droop: 1);
      final step = approachFoliage(from, to, 1 / 60);
      expect(step.droop, greaterThan(0));
      expect(step.droop, lessThan(0.1));
    });

    test('is framerate-independent', () {
      const from = FoliageState();
      const to = FoliageState(droop: 1);
      // One 100ms step must land in the same place as ten 10ms steps.
      final coarse = approachFoliage(from, to, 0.1);
      var fine = from;
      for (var i = 0; i < 10; i++) {
        fine = approachFoliage(fine, to, 0.01);
      }
      expect(fine.droop, closeTo(coarse.droop, 1e-9));
    });

    test('converges on the target', () {
      var s = const FoliageState();
      for (var i = 0; i < 600; i++) {
        s = approachFoliage(s, const FoliageState(droop: 1), 1 / 60);
      }
      expect(s.droop, closeTo(1.0, 1e-3));
    });
  });
}
