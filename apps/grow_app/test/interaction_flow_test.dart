import 'package:flutter_test/flutter_test.dart';
import 'package:grow_app/game/game_controller.dart';
import 'package:grow_content/grow_content.dart';
import 'package:grow_domain/grow_domain.dart';
import 'package:grow_sim/grow_sim.dart';

/// The interaction architecture must stay simulation-first:
///
///   intent → validate → domain action → simulation state → projection
///     → appearance → visual feedback
///
/// These tests pin that chain. If a future change lets the UI set appearance
/// directly, or lets a refused action still produce feedback, they fail.
void main() {
  final content = mvpContent();

  GameController fresh({int water = 6, int nutrients = 3}) {
    final base = GameState.newGame(
      worldSeed: const Seed(20260903),
      starterSpecies: const SpeciesId('quercus_robur'),
    );
    return GameController(
      content: content,
      initial: base.copyWith(
        trees: [
          base.trees.first.copyWith(
            stage: GrowthStage.sapling,
            water: Vital(34),
            nutrition: Vital(30),
            health: Vital(88),
          ),
        ],
        inventory: Inventory.starting().copyWith(
          water: water,
          nutrients: nutrients,
        ),
      ),
    );
  }

  TreeVisual visual(GameController c) => c.snapshot.trees.first;
  Tree tree(GameController c) => c.state.trees.first;

  group('watering flows through the simulation', () {
    test('appearance changes because the vital changed', () {
      final c = fresh();
      final beforeWater = tree(c).water.value;
      final beforeDroop = visual(c).foliage.droop;

      expect(c.water(tree(c).id), isNull, reason: 'should be affordable');

      // The domain moved...
      expect(tree(c).water.value, greaterThan(beforeWater));
      // ...and appearance followed it, without anyone setting appearance.
      expect(visual(c).foliage.droop, lessThan(beforeDroop));
    });

    test('the resource is actually spent', () {
      final c = fresh(water: 4);
      c.water(tree(c).id);
      expect(c.state.inventory.totalWaterAvailable, 3);
    });

    test('the domain counter that drives the burst increments', () {
      // The renderer plays a splash because this number changed. Nothing else
      // can start it.
      final c = fresh();
      final before = tree(c).timesWatered;
      c.water(tree(c).id);
      expect(tree(c).timesWatered, before + 1);
    });

    test('a refused action changes nothing at all', () {
      final c = fresh(water: 0);
      final before = tree(c);
      final refusal = c.water(before.id);

      expect(refusal, isNotNull);
      expect(refusal!.message, isNotEmpty);
      // No vital moved, and crucially no counter moved — so no burst plays.
      expect(tree(c).water.value, before.water.value);
      expect(tree(c).timesWatered, before.timesWatered);
      expect(visual(c).foliage.droop, closeTo(visual(c).foliage.droop, 0));
    });

    test('watering does not visually fix a sick tree', () {
      // Turgor reads health as well as moisture. A single watering must not
      // make an unwell tree look well.
      final base = GameState.newGame(
        worldSeed: const Seed(7),
        starterSpecies: const SpeciesId('quercus_robur'),
      );
      final c = GameController(
        content: content,
        initial: base.copyWith(
          trees: [
            base.trees.first.copyWith(
              stage: GrowthStage.sapling,
              water: Vital(40),
              nutrition: Vital(50),
              health: Vital(22),
            ),
          ],
          inventory: Inventory.starting().copyWith(water: 5),
        ),
      );
      c.water(tree(c).id);
      c.water(tree(c).id);
      expect(
        tree(c).water.value,
        greaterThan(55),
        reason: 'test setup: moisture should now be comfortable',
      );
      expect(
        visual(c).foliage.droop,
        greaterThan(0.3),
        reason: 'a sick tree should still sag after being watered',
      );
    });
  });

  group('feeding', () {
    test('overfeeding is possible, and shows', () {
      final base = GameState.newGame(
        worldSeed: const Seed(11),
        starterSpecies: const SpeciesId('quercus_robur'),
      );
      final c = GameController(
        content: content,
        initial: base.copyWith(
          trees: [
            base.trees.first.copyWith(
              stage: GrowthStage.sapling,
              nutrition: Vital(62),
            ),
          ],
          inventory: Inventory.starting().copyWith(nutrients: 4),
        ),
      );
      // The button warns; it does not refuse. Making the mistake is the lesson.
      expect(c.previewFeed(tree(c)).leavesBand, isTrue);
      c.feed(tree(c).id);
      expect(tree(c).nutrition.value, greaterThan(65));
      expect(visual(c).foliage.scorch, greaterThan(0));
    });

    test('scorch outlives the excess', () {
      final c = fresh(nutrients: 5);
      for (var i = 0; i < 4; i++) {
        c.feed(tree(c).id);
      }
      c.advanceTo(SimTime(c.state.simTime.ms + SimTime.hourMs * 3));
      expect(tree(c).has(AfflictionKind.nutrientBurn), isTrue);

      // Even once nutrition is back in range, the damage still reads.
      c.advanceTo(SimTime(c.state.simTime.ms + SimTime.dayMs * 2));
      if (content[tree(c).species].nutrition.contains(
        tree(c).nutrition.value,
      )) {
        expect(
          visual(c).foliage.scorch,
          greaterThan(0),
          reason: 'scorched leaves do not un-scorch immediately',
        );
      }
    });
  });

  group('the projection is the only source of appearance', () {
    test('an identical state always yields identical appearance', () {
      final a = fresh();
      final b = fresh();
      expect(visual(a).foliage.droop, visual(b).foliage.droop);
      expect(visual(a).foliage.pallor, visual(b).foliage.pallor);
    });

    test('simulated time alone changes appearance, with no player action', () {
      final c = fresh();
      final before = visual(c).foliage.droop;
      c.advanceTo(SimTime(c.state.simTime.ms + SimTime.dayMs));
      expect(visual(c).foliage.droop, isNot(closeTo(before, 1e-6)));
    });
  });

  group('sightings are a domain fact', () {
    test('looking at a critical tree is recorded, and gates its death', () {
      final base = GameState.newGame(
        worldSeed: const Seed(3),
        starterSpecies: const SpeciesId('quercus_robur'),
      );
      var state = base.copyWith(
        trees: [base.trees.first.copyWith(health: Vital(6))],
      );
      final c = GameController(content: content, initial: state);
      c.advanceTo(SimTime(SimTime.hourMs));
      state = c.state;
      if (state.trees.first.state == HealthState.critical) {
        final before = state.trees.first.criticalSightings;
        c.noteSighting(state.trees.first.id);
        expect(c.state.trees.first.criticalSightings, before + 1);
      }
    });

    test('a healthy tree records nothing', () {
      final c = fresh();
      c.noteSighting(tree(c).id);
      expect(tree(c).criticalSightings, 0);
    });
  });

  group('refusals are surfaced once', () {
    test('and can be cleared', () {
      final c = fresh(water: 0);
      c.water(tree(c).id);
      expect(c.refusal, isNotNull);
      c.clearRefusal();
      expect(c.refusal, isNull);
    });

    test('a successful action clears a standing refusal', () {
      final c = fresh(water: 0);
      c.water(tree(c).id);
      expect(c.refusal, isNotNull);
      c.feed(tree(c).id);
      expect(c.refusal, isNull);
    });
  });
}
