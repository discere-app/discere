enum INatEnrichmentPhase { idle, nameResolution, cover, base, inat, names }

class INatEnrichmentStatus {
  final bool isRunning;
  final bool hasPendingWork;
  final bool hasActiveHostCooldown;
  final INatEnrichmentPhase phase;
  final int completed;
  final int total;
  final int activeDeckCount;
  final int readyDeckCount;
  final int totalDeckCount;

  const INatEnrichmentStatus({
    required this.isRunning,
    required this.hasPendingWork,
    required this.hasActiveHostCooldown,
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
    hasActiveHostCooldown: false,
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

  INatEnrichmentStatus copyWith({
    bool? isRunning,
    bool? hasPendingWork,
    bool? hasActiveHostCooldown,
    INatEnrichmentPhase? phase,
    int? completed,
    int? total,
    int? activeDeckCount,
    int? readyDeckCount,
    int? totalDeckCount,
  }) {
    return INatEnrichmentStatus(
      isRunning: isRunning ?? this.isRunning,
      hasPendingWork: hasPendingWork ?? this.hasPendingWork,
      hasActiveHostCooldown:
          hasActiveHostCooldown ?? this.hasActiveHostCooldown,
      phase: phase ?? this.phase,
      completed: completed ?? this.completed,
      total: total ?? this.total,
      activeDeckCount: activeDeckCount ?? this.activeDeckCount,
      readyDeckCount: readyDeckCount ?? this.readyDeckCount,
      totalDeckCount: totalDeckCount ?? this.totalDeckCount,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is INatEnrichmentStatus &&
        other.isRunning == isRunning &&
        other.hasPendingWork == hasPendingWork &&
        other.hasActiveHostCooldown == hasActiveHostCooldown &&
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
    hasActiveHostCooldown,
    phase,
    completed,
    total,
    activeDeckCount,
    readyDeckCount,
    totalDeckCount,
  );
}
