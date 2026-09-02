import 'package:grow_domain/grow_domain.dart';

enum SimEventKind {
  growthStageUp,
  flowered,
  afflictionStarted,
  afflictionCleared,
  healthStateChanged,
  enteredDormancy,
  rainfall,
  animalVisit,
  discovery,
  becameSnag,
}

/// One notable thing that happened during a simulated window. These are what
/// the "while you were away" sequence renders.
class SimEvent {
  const SimEvent({
    required this.kind,
    required this.at,
    required this.message,
    this.treeId,
    this.magnitude = 0,
  });

  final SimEventKind kind;
  final SimTime at;
  final String message;
  final TreeId? treeId;
  final double magnitude;

  /// Ranks events for the welcome-back summary when the journal is capped.
  int get significance => switch (kind) {
    SimEventKind.becameSnag => 100,
    SimEventKind.growthStageUp => 90,
    SimEventKind.discovery => 85,
    SimEventKind.flowered => 70,
    SimEventKind.enteredDormancy => 65,
    SimEventKind.afflictionStarted => 60,
    SimEventKind.healthStateChanged => 50,
    SimEventKind.animalVisit => 40,
    SimEventKind.afflictionCleared => 35,
    SimEventKind.rainfall => 20,
  };

  @override
  String toString() => '[${kind.name}] $message';
}

/// Aggregates for a simulated window. Always produced, even when the detailed
/// journal is capped, so the summary screen never loses the headline numbers.
class SimulationDigest {
  const SimulationDigest({
    required this.elapsed,
    required this.growthByTree,
    required this.waterDeltaByTree,
    required this.rainHours,
    required this.dewGained,
    required this.stageUps,
    required this.enteredDormancy,
  });

  final Duration elapsed;
  final Map<TreeId, double> growthByTree;
  final Map<TreeId, double> waterDeltaByTree;
  final double rainHours;
  final int dewGained;
  final int stageUps;
  final bool enteredDormancy;

  bool get isEmpty => elapsed.inMinutes < 1;
}

class SimulationResult {
  const SimulationResult({
    required this.state,
    required this.journal,
    required this.digest,
  });

  final GameState state;
  final List<SimEvent> journal;
  final SimulationDigest digest;
}
