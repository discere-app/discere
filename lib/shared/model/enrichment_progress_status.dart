enum INatEnrichmentPhase { idle, nameResolution, cover, base, inat, names }

class INatEnrichmentStatus {
  final bool isRunning;
  final bool hasPendingWork;
  final INatEnrichmentPhase phase;
  final int completed;
  final int total;
  final int activeDeckCount;
  final int readyDeckCount;
  final int totalDeckCount;

  const INatEnrichmentStatus({
    required this.isRunning,
    required this.hasPendingWork,
    required this.phase,
    required this.completed,
    required this.total,
    this.activeDeckCount = 0,
    this.readyDeckCount = 0,
    this.totalDeckCount = 0,
  });

  static const idle = INatEnrichmentStatus(
    isRunning: false,
    hasPendingWork: false,
    phase: INatEnrichmentPhase.idle,
    completed: 0,
    total: 0,
    activeDeckCount: 0,
    readyDeckCount: 0,
    totalDeckCount: 0,
  );

  int get remainingDeckCount {
    final remaining = totalDeckCount - readyDeckCount;
    if (remaining <= 0) return 0;
    return remaining;
  }

  @override
  bool operator ==(Object other) {
    return other is INatEnrichmentStatus &&
        other.isRunning == isRunning &&
        other.hasPendingWork == hasPendingWork &&
        other.phase == phase &&
        other.completed == completed &&
        other.total == total &&
        other.activeDeckCount == activeDeckCount &&
        other.readyDeckCount == readyDeckCount &&
        other.totalDeckCount == totalDeckCount;
  }

  @override
  int get hashCode => Object.hash(
    isRunning,
    hasPendingWork,
    phase,
    completed,
    total,
    activeDeckCount,
    readyDeckCount,
    totalDeckCount,
  );
}
