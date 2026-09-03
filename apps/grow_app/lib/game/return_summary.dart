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
  List<SimEvent> get highlights => journal.take(4).toList();
}
