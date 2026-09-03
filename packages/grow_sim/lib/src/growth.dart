import 'package:grow_content/grow_content.dart';
import 'package:grow_domain/grow_domain.dart';

/// The result of adding growth to a tree.
class GrowthApplication {
  const GrowthApplication({
    required this.tree,
    required this.stagesGained,
    required this.applied,
  });

  const GrowthApplication.none(this.tree) : stagesGained = 0, applied = 0;

  final Tree tree;

  /// How many stage boundaries this crossed. Usually 0; more than 1 only when
  /// a large reward lands on an almost-finished short stage.
  final int stagesGained;

  /// How much of the requested growth actually landed, in points of the stage
  /// the tree started in. Less than requested only when the tree ran out of
  /// tree to be — there is nothing past Ancient.
  ///
  /// Callers must report *this*, not what they asked for. A completion screen
  /// that promises growth the tree did not make is a lie the player can see.
  final double applied;
}

/// Adds growth to a tree, carrying overflow across stage boundaries.
///
/// **The one place growth is applied.** The simulator's hourly accrual and a
/// focus session's reward both come through here, because they are the same
/// operation and had drifted apart: the reward path used to add points to a
/// clamped vital, so a session that should have finished a stage silently lost
/// everything above 100.
///
/// Growth is stored as a percentage of the *current* stage, and stages are not
/// the same length, so a point is not a fixed amount of tree. Overflow is
/// therefore converted through hours rather than carried across as a raw
/// percentage — otherwise finishing the 4-hour Sprout stage would spill four
/// hours' worth of progress into the 24-hour Seedling stage.
GrowthApplication addGrowth(Tree tree, TreeSpecies species, double points) {
  if (points <= 0 || !points.isFinite || tree.stage.isFinal) {
    return GrowthApplication.none(tree);
  }

  // Hours of growth per requested point, in the stage the caller measured in.
  final unitHours = species.hoursForStage(tree.stage) / 100.0;
  if (unitHours <= 0) return GrowthApplication.none(tree);

  var remainingHours = points * unitHours;
  var landedHours = 0.0;
  var stage = tree.stage;
  var value = tree.growth.value;
  var gained = 0;

  // Bounded by the stage count; the guard is against a content file that
  // declares a zero-length stage in the middle of the ladder.
  for (var i = 0; i <= GrowthStage.values.length; i++) {
    final stageHours = species.hoursForStage(stage);
    if (stageHours <= 0) break;

    final roomHours = (100.0 - value) / 100.0 * stageHours;
    if (remainingHours < roomHours) {
      value += remainingHours / stageHours * 100.0;
      landedHours += remainingHours;
      break;
    }

    remainingHours -= roomHours;
    landedHours += roomHours;
    if (stage.isFinal) break;

    stage = stage.next;
    value = 0;
    gained++;
    if (stage.isFinal) break; // nothing grows past Ancient
  }

  return GrowthApplication(
    tree: tree.copyWith(stage: stage, growth: Vital(value)),
    stagesGained: gained,
    applied: landedHours / unitHours,
  );
}
