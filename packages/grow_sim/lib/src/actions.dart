import 'package:grow_content/grow_content.dart';
import 'package:grow_domain/grow_domain.dart';

/// Why an action could not be taken. Expected failures, not exceptions.
enum ActionError {
  noSuchTree('That tree is no longer here.'),
  treeIsSnag('This is standing deadwood now. It can be cleared for seeds.'),
  noWater('You have no water left.'),
  noNutrients('You have no feed left.');

  const ActionError(this.message);
  final String message;
}

class ActionResult {
  const ActionResult.success(this.state) : error = null;
  const ActionResult.failure(this.error) : state = null;
  final GameState? state;
  final ActionError? error;

  bool get ok => state != null;
}

/// What an action would do, shown on the button before it is pressed.
///
/// The UI warns when the result leaves the safe band but never blocks the
/// action — the player is allowed to make the mistake, because making it is
/// how the system teaches.
class ActionPreview {
  const ActionPreview({
    required this.from,
    required this.to,
    required this.leavesBand,
    required this.enters,
  });

  final double from;
  final double to;
  final bool leavesBand;

  /// True when the action moves the tree *into* its ideal band.
  final bool enters;
}

/// Player actions. Separate from the simulator: these are discrete, immediate,
/// and always player-initiated.
class Actions {
  const Actions(this.content);
  final ContentBundle content;

  ActionPreview previewWater(Tree tree) {
    final species = content[tree.species];
    final to = (tree.water.value + species.absorption).clamp(0.0, 100.0);
    return ActionPreview(
      from: tree.water.value,
      to: to,
      leavesBand: !species.water.contains(to),
      enters:
          !species.water.contains(tree.water.value) &&
          species.water.contains(to),
    );
  }

  ActionPreview previewFeed(Tree tree) {
    final species = content[tree.species];
    final to = (tree.nutrition.value + 22.0).clamp(0.0, 100.0);
    return ActionPreview(
      from: tree.nutrition.value,
      to: to,
      leavesBand: !species.nutrition.contains(to),
      enters:
          !species.nutrition.contains(tree.nutrition.value) &&
          species.nutrition.contains(to),
    );
  }

  ActionResult water(GameState state, TreeId id) {
    final tree = state.treeById(id);
    if (tree == null) return const ActionResult.failure(ActionError.noSuchTree);
    if (tree.isSnag) return const ActionResult.failure(ActionError.treeIsSnag);

    final inv = state.inventory;
    if (inv.totalWaterAvailable <= 0) {
      return const ActionResult.failure(ActionError.noWater);
    }
    // Spend dew first: it is capped and would otherwise be wasted.
    final useDew = inv.dew > 0;
    final species = content[tree.species];

    return ActionResult.success(
      state.copyWith(
        trees: _replace(
          state.trees,
          tree.copyWith(
            water: tree.water + species.absorption,
            timesWatered: tree.timesWatered + 1,
            lastTendedAt: state.simTime,
          ),
        ),
        inventory: useDew
            ? inv.copyWith(dew: inv.dew - 1)
            : inv.copyWith(water: inv.water - 1),
        lastInteractionAt: state.simTime,
      ),
    );
  }

  ActionResult feed(GameState state, TreeId id) {
    final tree = state.treeById(id);
    if (tree == null) return const ActionResult.failure(ActionError.noSuchTree);
    if (tree.isSnag) return const ActionResult.failure(ActionError.treeIsSnag);
    if (state.inventory.nutrients <= 0) {
      return const ActionResult.failure(ActionError.noNutrients);
    }
    return ActionResult.success(
      state.copyWith(
        trees: _replace(
          state.trees,
          tree.copyWith(
            nutrition: tree.nutrition + 22.0,
            timesFed: tree.timesFed + 1,
            lastTendedAt: state.simTime,
          ),
        ),
        inventory: state.inventory.copyWith(
          nutrients: state.inventory.nutrients - 1,
        ),
        lastInteractionAt: state.simTime,
      ),
    );
  }

  /// Records that the player has actually looked at a tree while it was in
  /// trouble. Death requires two of these, so nobody loses a tree they never
  /// had a chance to save.
  static GameState noteSighting(GameState state, TreeId id) {
    final tree = state.treeById(id);
    if (tree == null || tree.state != HealthState.critical) return state;
    return state.copyWith(
      trees: _replace(
        state.trees,
        tree.copyWith(criticalSightings: tree.criticalSightings + 1),
      ),
    );
  }

  static List<Tree> _replace(List<Tree> trees, Tree updated) => [
    for (final t in trees) t.id == updated.id ? updated : t,
  ];
}
