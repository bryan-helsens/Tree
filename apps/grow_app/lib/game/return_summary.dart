import 'package:grow_domain/grow_domain.dart';
import 'package:grow_sim/grow_sim.dart';

/// What happened while the player was away.
///
/// Assembled from the simulation's own digest and journal, so it reports what
/// the world actually did rather than a separately maintained activity log.
class ReturnSummary {
  const ReturnSummary({
    required this.away,
    required this.digest,
    required this.journal,
    this.sessionOutcome,
  });

  const ReturnSummary.none()
    : away = Duration.zero,
      digest = null,
      journal = const [],
      sessionOutcome = null;

  final Duration away;
  final SimulationDigest? digest;
  final List<SimEvent> journal;

  /// Set when a focus session finished while the app was closed. The reward
  /// is already committed by the time this exists — the return screen reports
  /// it, it does not grant it.
  final SessionOutcome? sessionOutcome;

  /// Whether there is anything worth showing.
  ///
  /// A twenty-minute gap is the threshold: shorter than that and a "while you
  /// were away" screen is an interruption, not a reward.
  bool get isWorthShowing =>
      sessionOutcome != null || away >= const Duration(minutes: 20);

  int get stageUps => digest?.stageUps ?? 0;
  int get dewGained => digest?.dewGained ?? 0;
  bool get rained => (digest?.rainHours ?? 0) > 0.25;
  bool get rested => digest?.enteredDormancy ?? false;

  double growthFor(TreeId id) => digest?.growthByTree[id] ?? 0;

  /// The handful of things worth saying, most significant first.
  ///
  /// Sorted by [SimEvent.significance], not by time. A player who was away
  /// two days has a journal full of rainfall; the one thing they want to know
  /// is that their oak became a sapling, and it must not be pushed off the
  /// end of the list by weather.
  List<SimEvent> get highlights {
    final ranked = [...journal]
      ..sort((a, b) {
        final bySignificance = b.significance.compareTo(a.significance);
        return bySignificance != 0
            ? bySignificance
            : b.at.ms.compareTo(a.at.ms);
      });
    return ranked.take(3).toList();
  }

  /// How long the player was away, in words rather than a measurement.
  ///
  /// "You were away for 187 minutes" is a productivity report. This is the
  /// difference between the game noticing you were gone and the game timing
  /// you, and it is the whole tone of the return screen.
  String get awayInWords {
    final minutes = away.inMinutes;
    if (minutes < 45) return 'a little while';
    if (minutes < 90) return 'about an hour';
    if (away.inHours < 5) return 'a few hours';
    if (away.inHours < 10) return 'most of the day';
    if (away.inHours < 30) return 'a day';
    final days = (away.inHours / 24).round();
    return days >= 7 ? 'over a week' : '$days days';
  }
}
