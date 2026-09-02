/// Visible problems a tree can develop. Each maps to a renderer uniform and to
/// a line of explanatory copy, so the player can always tell what went wrong.
enum AfflictionKind {
  /// Overwatering past the band for a sustained period.
  fungus('Fungus', 'The soil has stayed wet too long.'),

  /// Feeding past the nutrition band.
  nutrientBurn('Nutrient burn', 'Too much feed has scorched the leaf edges.'),

  /// More likely on stressed or waterlogged trees.
  pest('Pests', 'Something is eating the new growth.'),

  /// Sustained drought.
  drought('Drought stress', 'The soil has been dry for a long time.');

  const AfflictionKind(this.label, this.explanation);
  final String label;
  final String explanation;
}

class Affliction {
  const Affliction({
    required this.kind,
    required this.severity,
    required this.startedAtMs,
  });

  final AfflictionKind kind;

  /// 0..1. Drives both the health penalty and the strength of the visual.
  final double severity;
  final int startedAtMs;

  Affliction copyWith({double? severity}) => Affliction(
    kind: kind,
    severity: (severity ?? this.severity).clamp(0.0, 1.0).toDouble(),
    startedAtMs: startedAtMs,
  );

  @override
  bool operator ==(Object other) =>
      other is Affliction &&
      other.kind == kind &&
      other.severity == severity &&
      other.startedAtMs == startedAtMs;

  @override
  int get hashCode => Object.hash(kind, severity, startedAtMs);

  @override
  String toString() => '${kind.label}(${(severity * 100).toStringAsFixed(0)}%)';
}
