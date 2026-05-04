enum INatEnrichmentPhase { idle, nameResolution, cover, base, inat, names }

class INatEnrichmentStatus {
  final bool isRunning;
  final bool hasPendingWork;

  /// True when at least one job is actively running or queued to run imminently
  /// (queued, runningForeground, runningBackground, pausedBySystem).
  /// False when all pending jobs are in retryScheduled state waiting for the
  /// host cooldown to clear. Use this for banner/notification visibility.
  final bool hasActiveWork;

  final bool hasActiveHostCooldown;
  final bool preferBackgroundMessaging;
  final INatEnrichmentPhase phase;
  final int completed;
  final int total;
  final int activeDeckCount;
  final int readyDeckCount;
  final int totalDeckCount;

  const INatEnrichmentStatus({
    required this.isRunning,
    required this.hasPendingWork,
    required this.hasActiveWork,
    required this.hasActiveHostCooldown,
    this.preferBackgroundMessaging = false,
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
    hasActiveWork: false,
    hasActiveHostCooldown: false,
    preferBackgroundMessaging: false,
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
    bool? hasActiveWork,
    bool? hasActiveHostCooldown,
    bool? preferBackgroundMessaging,
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
      hasActiveWork: hasActiveWork ?? this.hasActiveWork,
      hasActiveHostCooldown:
          hasActiveHostCooldown ?? this.hasActiveHostCooldown,
      preferBackgroundMessaging:
          preferBackgroundMessaging ?? this.preferBackgroundMessaging,
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
        other.hasActiveWork == hasActiveWork &&
        other.hasActiveHostCooldown == hasActiveHostCooldown &&
        other.preferBackgroundMessaging == preferBackgroundMessaging &&
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
    hasActiveWork,
    hasActiveHostCooldown,
    preferBackgroundMessaging,
    phase,
    completed,
    total,
    activeDeckCount,
    readyDeckCount,
    totalDeckCount,
  );
}
