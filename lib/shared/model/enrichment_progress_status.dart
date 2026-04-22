enum INatEnrichmentPhase { idle, nameResolution, cover, base, inat, names }

class INatEnrichmentStatus {
  final bool isRunning;
  final INatEnrichmentPhase phase;
  final int completed;
  final int total;
  final int activeDeckCount;

  const INatEnrichmentStatus({
    required this.isRunning,
    required this.phase,
    required this.completed,
    required this.total,
    this.activeDeckCount = 0,
  });

  static const idle = INatEnrichmentStatus(
    isRunning: false,
    phase: INatEnrichmentPhase.idle,
    completed: 0,
    total: 0,
    activeDeckCount: 0,
  );

  @override
  bool operator ==(Object other) {
    return other is INatEnrichmentStatus &&
        other.isRunning == isRunning &&
        other.phase == phase &&
        other.completed == completed &&
        other.total == total &&
        other.activeDeckCount == activeDeckCount;
  }

  @override
  int get hashCode =>
      Object.hash(isRunning, phase, completed, total, activeDeckCount);
}
