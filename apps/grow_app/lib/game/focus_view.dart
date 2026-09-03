import 'package:grow_domain/grow_domain.dart';

/// What the focus surface should be showing, derived from the save.
///
/// A projection in the same sense as `WorldProjector`: it reads domain state
/// and reports an appearance. It holds nothing, decides nothing, and cannot be
/// assigned to. If the session record says a session is running, one is
/// running — there is no second copy of that fact in a widget.
///
/// The one thing genuinely *not* here is the duration a player is scrolling
/// through in the picker before they commit. That is not a session and not
/// domain state; it becomes both the instant `start()` is called.
sealed class FocusView {
  const FocusView();

  /// Reads [state] and says what belongs on screen.
  factory FocusView.of(GameState state) {
    final session = state.session;
    if (session == null) return const FocusIdle();

    return switch (session.phase) {
      FocusPhase.running => FocusRunning(
        planned: session.planned,
        elapsed: session.elapsedAt(state.simTime),
        remaining: session.remainingAt(state.simTime),
        progress: session.progressAt(state.simTime),
      ),
      // Finished but not yet claimed. Transient — the controller settles a
      // session on the very next advance — but a frame can land here, and it
      // must not flash the idle surface at someone who just finished.
      FocusPhase.completed || FocusPhase.abandoned => const FocusSettling(),
      FocusPhase.claimed => FocusFinished(
        outcome: session.outcome!,
        endedEarly: session.elapsedAt(state.simTime) < session.planned,
      ),
    };
  }
}

/// No session. The forest, and an invitation.
class FocusIdle extends FocusView {
  const FocusIdle();
}

/// A session is underway.
class FocusRunning extends FocusView {
  const FocusRunning({
    required this.planned,
    required this.elapsed,
    required this.remaining,
    required this.progress,
  });

  final Duration planned;
  final Duration elapsed;
  final Duration remaining;

  /// 0..1 through the planned duration.
  final double progress;

  /// Rounded up, and never shown finer than a minute.
  ///
  /// A per-second countdown is the anxious version of this screen: it invites
  /// you to watch it. Minutes are enough to know where you are.
  int get minutesLeft => (remaining.inSeconds / 60).ceil();
}

/// Finished, reward not yet committed. Lasts at most one frame in practice.
class FocusSettling extends FocusView {
  const FocusSettling();
}

/// Finished and paid. The reward is **already committed** — this reports it.
class FocusFinished extends FocusView {
  const FocusFinished({required this.outcome, required this.endedEarly});

  final SessionOutcome outcome;

  /// The player stopped before the planned end. Not a failure, and the copy
  /// must not treat it as one.
  final bool endedEarly;
}
