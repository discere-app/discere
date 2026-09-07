/// Model types for the deck cover job: its status enums and the persisted
/// record.
///
/// Persisted by [EnrichmentJobRepository]; consumed by `CoverJobRunner`, the
/// queue service, and the UI-facing state derivations. The cover image is the
/// only job the enrichment queue runs — species and taxonomy enrichment is
/// tracked in `EnrichmentOwnershipRepository`'s queue tables instead, driven by
/// `BaseWorker`/`INatWorker` and keyed by the
/// `EnrichmentCapability`/`EnrichmentWorkState` vocabulary they share.
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

/// How far the cover fetch for a deck has got.
///
/// [skipped] is not a failure: a deck scheduled without a cover URL has
/// nothing to fetch, and is born skipped so it counts as finished rather than
/// waiting forever for a download that will never be attempted.
///
/// The wire names are spelled out rather than taken from [name] so renaming a
/// value here cannot silently change what is already in the database.
enum CoverFetchState {
  pending('pending'),
  running('running'),
  succeeded('succeeded'),
  failed('failed'),
  skipped('skipped');

  final String wireName;

  const CoverFetchState(this.wireName);

  static CoverFetchState fromWire(String wireName) => values.firstWhere(
    (state) => state.wireName == wireName,
    orElse: () => throw ArgumentError.value(
      wireName,
      'wireName',
      'unknown cover fetch state',
    ),
  );

  bool get isTerminal =>
      this == succeeded || this == failed || this == skipped;
}

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
  final CoverFetchState coverState;

  const EnrichmentJobRecord({
    required this.deckId,
    required this.status,
    required this.attemptedAt,
    required this.completedAt,
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
    required this.coverState,
  });

  /// Both halves are needed: a cancelled or completed job may still carry a
  /// non-terminal cover state (cancelling does not rewrite it), and a job
  /// whose status has not caught up yet is still work while its cover is
  /// pending or running.
  bool get hasPendingWork {
    if (status == EnrichmentJobStatus.cancelled ||
        status == EnrichmentJobStatus.completed ||
        status == EnrichmentJobStatus.failedPermanent) {
      return false;
    }
    return !coverState.isTerminal;
  }
}
