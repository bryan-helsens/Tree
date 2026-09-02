import 'growth_stage.dart';

/// Health bands, reported with hysteresis so the UI never flickers.
///
/// Every state carries a glyph and a word as well as its colour, because
/// colour is never the only carrier of state (Design Charter C6).
enum HealthState {
  thriving('Thriving', '✦'),
  healthy('Healthy', '●'),
  stressed('Stressed', '◐'),
  ailing('Ailing', '◒'),
  critical('Needs help', '○'),

  /// Entered after a long absence. Vitals drift toward a resting equilibrium
  /// and health decays at a quarter rate with a floor. A tree can never die
  /// from absence alone (Design Charter C1).
  dormant('Resting', '◌'),

  /// Standing deadwood. Not deletion: a snag still hosts wildlife, still counts
  /// toward ecosystem diversity, and yields Heartwood seeds.
  snag('Snag', '†');

  const HealthState(this.label, this.glyph);
  final String label;
  final String glyph;

  bool get isAlive => this != HealthState.snag;
  bool get needsAttention =>
      this == HealthState.stressed ||
      this == HealthState.ailing ||
      this == HealthState.critical;
}

/// Hysteresis thresholds. A state is entered at [enterAt] and only left once
/// health crosses [leaveAt], which is deliberately further away.
class HealthThresholds {
  const HealthThresholds._();

  static const double thrivingEnter = 88;
  static const double thrivingLeave = 82;
  static const double thrivingComfort = 0.90;
  static const double healthyEnter = 70;
  static const double healthyLeave = 64;
  static const double stressedEnter = 45;
  static const double stressedLeave = 39;
  static const double ailingEnter = 20;
  static const double ailingLeave = 15;
  static const double criticalLeave = 26;

  /// Resolves the reported state from raw health, comfort, and the state we
  /// were previously in.
  static HealthState resolve({
    required double health,
    required double comfort,
    required HealthState previous,
  }) {
    if (previous == HealthState.snag) return HealthState.snag;

    // Leaving the current state requires crossing the further threshold.
    switch (previous) {
      case HealthState.thriving:
        if (health >= thrivingLeave && comfort >= thrivingComfort * 0.9) {
          return HealthState.thriving;
        }
      case HealthState.healthy:
        if (health >= healthyLeave && health < thrivingEnter) {
          return HealthState.healthy;
        }
      case HealthState.stressed:
        if (health >= stressedLeave && health < healthyEnter) {
          return HealthState.stressed;
        }
      case HealthState.ailing:
        if (health >= ailingLeave && health < stressedEnter) {
          return HealthState.ailing;
        }
      case HealthState.critical:
        if (health < criticalLeave) return HealthState.critical;
      case HealthState.dormant:
      case HealthState.snag:
        break;
    }

    if (health >= thrivingEnter && comfort >= thrivingComfort) {
      return HealthState.thriving;
    }
    if (health >= healthyEnter) return HealthState.healthy;
    if (health >= stressedEnter) return HealthState.stressed;
    if (health >= ailingEnter) return HealthState.ailing;
    return HealthState.critical;
  }
}

/// Growth-stage-aware description used by the accessibility layer.
String describeTreeState(HealthState state, GrowthStage stage) =>
    '${stage.label}, ${state.label.toLowerCase()}';
