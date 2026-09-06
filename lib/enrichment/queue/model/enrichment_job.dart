/// Model types for the deck cover job: job/stage status enums and the
/// persisted job record.
///
/// Persisted by [EnrichmentJobRepository]; consumed by `CoverJobRunner`, the
/// queue service, and the UI-facing state derivations. Species/taxonomy
/// enrichment no longer goes through a job at all — see `BaseWorker`/
/// `INatWorker`, `EnrichmentWorkRepository`'s queue tables, and the
/// `EnrichmentCapability`/`EnrichmentWorkState` vocabulary they share. The
/// cover image is the only stage a job has ever run since migration v12,
/// which deleted every other stage row.
library;

enum EnrichmentJobStatus {
  queued,
  runningForeground,
  runningBackground,
  pausedBySystem,
  retryScheduled,
  cancelled,
  completed,
  failedTemporary,
  failedPermanent,
}

/// Only [cover] remains: migration v12 deleted every `enrichment_job_stages`
/// row with another stage, so no persisted value outside this set can be read
/// back. Species-level work is keyed by `EnrichmentCapability` instead.
enum EnrichmentStage { cover }

enum EnrichmentStageState { pending, running, succeeded, failed, skipped }

enum EnrichmentRunnerKind { foreground, background }

class EnrichmentJobPayload {
  final String? coverImageUrl;

  const EnrichmentJobPayload({this.coverImageUrl});

  Map<String, dynamic> toJson() => {'coverImageUrl': coverImageUrl};

  factory EnrichmentJobPayload.fromJson(Map<String, dynamic> json) {
    return EnrichmentJobPayload(
      coverImageUrl: json['coverImageUrl'] as String?,
    );
  }

  EnrichmentJobPayload copyWith({String? coverImageUrl}) {
    return EnrichmentJobPayload(
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
    );
  }
}

class EnrichmentJobRecord {
  final String deckId;
  final EnrichmentJobStatus status;
  final DateTime? attemptedAt;
  final DateTime? completedAt;
  final EnrichmentStage? currentStage;
  final EnrichmentJobPayload payload;
  final String? failureKind;
  final String? lastError;
  final int progressCompleted;
  final int progressTotal;
  final int retryCount;
  final DateTime? nextAttemptAt;
  final String? leaseOwner;
  final DateTime? leaseExpiresAt;
  final DateTime updatedAt;
  final Map<EnrichmentStage, EnrichmentStageState> stageStates;

  const EnrichmentJobRecord({
    required this.deckId,
    required this.status,
    required this.attemptedAt,
    required this.completedAt,
    required this.currentStage,
    required this.payload,
    required this.failureKind,
    required this.lastError,
    required this.progressCompleted,
    required this.progressTotal,
    required this.retryCount,
    required this.nextAttemptAt,
    required this.leaseOwner,
    required this.leaseExpiresAt,
    required this.updatedAt,
    required this.stageStates,
  });

  bool get hasPendingWork {
    if (status == EnrichmentJobStatus.cancelled ||
        status == EnrichmentJobStatus.completed ||
        status == EnrichmentJobStatus.failedPermanent) {
      return false;
    }
    return stageStates.values.any(
          (state) => state == EnrichmentStageState.pending,
        ) ||
        stageStates.values.any(
          (state) => state == EnrichmentStageState.running,
        );
  }
}
