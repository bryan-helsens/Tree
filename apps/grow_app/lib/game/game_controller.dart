import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:grow_content/grow_content.dart';
import 'package:grow_data/grow_data.dart';
import 'package:grow_domain/grow_domain.dart';
import 'package:grow_sim/grow_sim.dart';

import 'return_summary.dart';
import 'time_authority.dart';

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
    SaveRepository? repository,
    TimeAuthority? clock,
  }) : _content = content,
       _state = initial,
       _simulator = simulator ?? Simulator(content: content),
       _actions = Actions(content),
       _projector = WorldProjector(content: content),
       _machine = FocusMachine(content: content),
       _repository = repository,
       _clock = clock {
    _snapshot = _projector.project(_state);
  }

  final ContentBundle _content;
  final Simulator _simulator;
  final Actions _actions;
  final WorldProjector _projector;
  final FocusMachine _machine;
  final SaveRepository? _repository;
  final TimeAuthority? _clock;

  static const ClockGuard _guard = ClockGuard();

  GameState _state;
  late WorldSnapshot _snapshot;
  ActionRefusal? _refusal;
  ReturnSummary _lastReturn = const ReturnSummary.none();
  int _sessionCounter = 0;

  GameState get state => _state;
  WorldSnapshot get snapshot => _snapshot;
  ContentBundle get content => _content;

  /// The most recent refusal, for the UI to surface once and then clear.
  ActionRefusal? get refusal => _refusal;

  /// What happened while the player was away, from the last resume.
  ReturnSummary get lastReturn => _lastReturn;

  FocusSession? get session => _state.session;

  /// A finished session whose reward is committed and not yet acknowledged.
  SessionOutcome? get unacknowledgedOutcome =>
      _state.session?.phase == FocusPhase.claimed
      ? _state.session?.outcome
      : null;

  void clearRefusal() {
    if (_refusal == null) return;
    _refusal = null;
    notifyListeners();
  }

  /// Loads the save, credits the time that passed, and settles any session.
  ///
  /// This is the crash-recovery path and the ordinary-launch path — the same
  /// code, because a launch after a crash differs only in what the save
  /// happens to contain. A session that finished while the process was dead is
  /// completed and claimed here, exactly once.
  Future<ReturnSummary> resume() async {
    final repository = _repository;
    final clock = _clock;

    final loaded = repository == null ? null : await repository.load();
    var state = loaded ?? _state;

    if (clock == null) {
      _apply(state);
      return _lastReturn = const ReturnSummary.none();
    }

    final reading = clock.now();
    if (state.clock.isFresh) {
      // First run of this save: record where the clocks are and credit
      // nothing. There is no interval to reason about yet.
      //
      // The anchor has to be *persisted*, or the next launch finds a fresh
      // clock again and can never compute an interval — the game would never
      // credit any offline time at all.
      _apply(state.copyWith(clock: _guard.anchor(state, reading)));
      await _persist();
      return _lastReturn = const ReturnSummary.none();
    }

    final advance = _guard.advance(state, reading);
    final before = state.simTime;
    final result = _simulator.run(
      state: state.copyWith(clock: advance.meta),
      to: advance.target,
    );

    final settled = _settle(result.state);
    state = settled.state;
    _apply(state);
    await _persist();

    return _lastReturn = ReturnSummary(
      away: Duration(milliseconds: state.simTime.ms - before.ms),
      digest: result.digest,
      journal: result.journal,
      sessionOutcome: settled.outcome,
    );
  }

  /// Advances the simulation to [to]. The same call the offline catch-up uses.
  void advanceTo(SimTime to) {
    final result = _simulator.run(state: _state, to: to);
    if (result.digest.elapsed == Duration.zero) return;
    _apply(_settle(result.state).state);
  }

  /// Advances by a wall-clock delta. Used by the foreground ticker; offline
  /// catch-up goes through [advanceTo] with a trusted elapsed time instead.
  void tick(Duration delta) =>
      advanceTo(SimTime(_state.simTime.ms + delta.inMilliseconds));

  ActionRefusal? water(TreeId id) => _perform(() => _actions.water(_state, id));

  ActionRefusal? feed(TreeId id) => _perform(() => _actions.feed(_state, id));

  // ── focus sessions ────────────────────────────────────────────────────

  /// Starts a session and **waits for it to be durable**.
  ///
  /// Fire-and-forget would leave a window in which the session exists in
  /// memory but not on disk; a process death inside that window loses a
  /// session the player has already begun. The await is the guarantee.
  Future<ActionRefusal?> startSession(Duration planned) async {
    final wallMs = _clock?.now().wallMs ?? 0;
    final transition = _machine.start(
      _state,
      planned: planned,
      id:
          'session-${_state.worldSeed.raw}-${_state.simTime.ms}-'
          '${_sessionCounter++}',
      wallMs: wallMs,
    );
    if (!transition.ok) {
      _refusal = ActionRefusal(transition.refusal!.message);
      notifyListeners();
      return _refusal;
    }
    _refusal = null;
    _apply(transition.state!);
    await _persist();
    return null;
  }

  /// The player stops early. Not a failure: the time spent is still paid for.
  Future<ActionRefusal?> endSessionEarly() async {
    final ended = _machine.endEarly(_state);
    if (!ended.ok) {
      _refusal = ActionRefusal(ended.refusal!.message);
      notifyListeners();
      return _refusal;
    }
    _refusal = null;
    _apply(_settle(ended.state!).state);
    await _persist();
    return null;
  }

  /// Acknowledges a claimed session so another can begin. The reward was
  /// already committed; this only clears the record.
  Future<void> dismissSession() async {
    final dismissed = _machine.dismiss(_state);
    if (!dismissed.ok) return;
    _apply(dismissed.state!);
    await _persist();
  }

  /// Evaluates a session against the clock and commits any reward waiting.
  ///
  /// Claiming is never gated on the player tapping anything: a reward that
  /// depends on being acknowledged is a reward that can be lost. The UI shows
  /// what was already committed.
  ({GameState state, SessionOutcome? outcome}) _settle(GameState state) {
    var next = _machine.evaluate(state);
    if (!(next.session?.phase.awaitsReward ?? false)) {
      return (state: next, outcome: null);
    }
    final claimed = _machine.claim(next);
    if (!claimed.ok) return (state: next, outcome: null);
    next = claimed.state!;
    return (state: next, outcome: claimed.outcome);
  }

  Future<void> _persist() async {
    final repository = _repository;
    if (repository == null) return;
    try {
      await repository.save(_state);
    } catch (_) {
      // A failed save is not a reason to lose the running game. The next
      // write will carry the same state forward.
    }
  }

  /// Called when the app is backgrounded. The save's timestamp is what the
  /// next resume reasons about, so this is the most important write there is.
  Future<void> onPaused() async {
    final clock = _clock;
    if (clock != null) {
      _state = _state.copyWith(clock: _guard.anchor(_state, clock.now()));
    }
    await _persist();
  }

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
