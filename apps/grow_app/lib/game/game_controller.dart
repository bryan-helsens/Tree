import 'package:flutter/foundation.dart';
import 'package:grow_content/grow_content.dart';
import 'package:grow_domain/grow_domain.dart';
import 'package:grow_sim/grow_sim.dart';

/// Why an action could not be taken, phrased for a person.
class ActionRefusal {
  const ActionRefusal(this.message);
  final String message;
}

/// Holds the game and is the only thing allowed to change it.
///
/// Every player action follows one path:
///
///   intent → validate → domain action → new GameState → re-project
///     → new FoliageState → renderer reacts
///
/// Nothing here touches visual state, and nothing downstream invents any. A
/// watering animation is not something the button plays; it is something the
/// renderer does *because* the tree's moisture and its watering count changed.
class GameController extends ChangeNotifier {
  GameController({
    required ContentBundle content,
    required GameState initial,
    Simulator? simulator,
  }) : _content = content,
       _state = initial,
       _simulator = simulator ?? Simulator(content: content),
       _actions = Actions(content),
       _projector = WorldProjector(content: content) {
    _snapshot = _projector.project(_state);
  }

  final ContentBundle _content;
  final Simulator _simulator;
  final Actions _actions;
  final WorldProjector _projector;

  GameState _state;
  late WorldSnapshot _snapshot;
  ActionRefusal? _refusal;

  GameState get state => _state;
  WorldSnapshot get snapshot => _snapshot;
  ContentBundle get content => _content;

  /// The most recent refusal, for the UI to surface once and then clear.
  ActionRefusal? get refusal => _refusal;

  void clearRefusal() {
    if (_refusal == null) return;
    _refusal = null;
    notifyListeners();
  }

  /// Advances the simulation to [to]. The same call the offline catch-up uses.
  void advanceTo(SimTime to) {
    final result = _simulator.run(state: _state, to: to);
    if (result.digest.elapsed == Duration.zero) return;
    _apply(result.state);
  }

  /// Advances by a wall-clock delta. Used by the foreground ticker; offline
  /// catch-up goes through [advanceTo] with a trusted elapsed time instead.
  void tick(Duration delta) =>
      advanceTo(SimTime(_state.simTime.ms + delta.inMilliseconds));

  ActionRefusal? water(TreeId id) => _perform(() => _actions.water(_state, id));

  ActionRefusal? feed(TreeId id) => _perform(() => _actions.feed(_state, id));

  /// Records that the player has looked at a tree while it was in trouble.
  /// Death requires two of these, so this is a real domain fact, not telemetry.
  void noteSighting(TreeId id) => _apply(Actions.noteSighting(_state, id));

  ActionRefusal? _perform(ActionResult Function() action) {
    final result = action();
    if (!result.ok) {
      _refusal = ActionRefusal(result.error!.message);
      notifyListeners();
      return _refusal;
    }
    _refusal = null;
    _apply(result.state!);
    return null;
  }

  void _apply(GameState next) {
    _state = next;
    // The projection is the only place appearance is decided.
    _snapshot = _projector.project(next);
    notifyListeners();
  }

  /// What a water action would do, for the button to preview. Read-only.
  ActionPreview previewWater(Tree tree) => _actions.previewWater(tree);

  ActionPreview previewFeed(Tree tree) => _actions.previewFeed(tree);

  TreeSpecies speciesOf(Tree tree) => _content[tree.species];
}
