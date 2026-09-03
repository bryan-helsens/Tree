import 'package:grow_domain/grow_domain.dart';
import 'package:grow_sim/grow_sim.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  final species = content[oak];

  group('a session reward lands in full', () {
    test('growth that crosses a stage boundary is not clipped away', () {
      // 96% of the way through a stage, with a reward big enough to finish it.
      final before = established(stage: GrowthStage.seedling).copyWith(
        trees: [
          established(
            stage: GrowthStage.seedling,
          ).trees.first.copyWith(growth: Vital(96)),
        ],
      );

      final yield_ = const FocusEconomy().yieldFor(
        minutes: 45,
        sessionIndexToday: 0,
        streakDays: 0,
        gpAlreadyEarnedToday: 0,
        deepFocusBonusAlreadyUsed: false,
      );
      expect(
        yield_.growthInjection,
        greaterThan(4.0),
        reason: 'the fixture only bites if the reward exceeds the room left',
      );

      final applied = applyFocusYield(before, yield_, content: content);
      final tree = applied.state.trees.first;

      // The tree must have moved on, not stopped dead at 100.
      expect(tree.stage, GrowthStage.sapling);

      // And the whole reward must be accounted for, in real growth time.
      final hourPoint = species.hoursForStage(GrowthStage.seedling) / 100;
      final landedHours =
          (100 - 96) * hourPoint +
          tree.growth.value / 100 * species.hoursForStage(GrowthStage.sapling);
      expect(
        landedHours,
        closeTo(yield_.growthInjection * hourPoint, 1e-9),
        reason: 'every awarded point must survive the stage boundary',
      );
      expect(applied.growthApplied, closeTo(yield_.growthInjection, 1e-9));
    });

    test('a fully grown tree reports the growth it could not use', () {
      final base = established(stage: GrowthStage.ancient);
      final yield_ = const FocusEconomy().yieldFor(
        minutes: 30,
        sessionIndexToday: 0,
        streakDays: 0,
        gpAlreadyEarnedToday: 0,
        deepFocusBonusAlreadyUsed: false,
      );

      final applied = applyFocusYield(base, yield_, content: content);

      // Nothing left to grow — so the completion screen must not claim any.
      expect(applied.growthApplied, 0);
      expect(applied.state.trees.first.stage, GrowthStage.ancient);
      // The rest of the reward is still paid.
      expect(applied.state.inventory.water, greaterThan(base.inventory.water));
    });
  });
}
