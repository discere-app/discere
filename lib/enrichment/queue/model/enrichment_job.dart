/// Model types for the deck cover job: job/stage status enums and the
/// persisted job record.
///
/// Persisted by [EnrichmentJobRepository]; consumed by `CoverJobRunner`, the
/// queue service, and the UI-facing state derivations. Species/taxonomy
/// enrichment no longer goes through a job at all — see `BaseWorker`/
/// `INatWorker` and `EnrichmentWorkRepository`'s queue tables. [cover] is the
/// only stage a job ever runs now; [EnrichmentStage]'s other values
/// (`base`/`inatPrimary`/`names`/`inatBackfill`) survive only as the shared
/// capability-name vocabulary those queue tables use (see
/// `EnrichmentWorkRepository`'s `_capabilityName`).
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

enum EnrichmentStage { cover, base, inatPrimary, names, inatBackfill }

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
