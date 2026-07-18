/// Model types for the deck-enrichment job queue: job/stage status enums,
/// the checkpointable job payload, and the persisted job record.
///
/// Persisted by [EnrichmentJobRepository]; consumed by the executor, the
/// queue service, and the UI-facing state derivations.
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

enum EnrichmentStage {
  nameResolution,
  cover,
  base,
  inatPrimary,
  names,
  inatBackfill,
}

enum EnrichmentStageState { pending, running, succeeded, failed, skipped }

enum EnrichmentRunnerKind { foreground, background }

class EnrichmentJobPayload {
  final List<String> speciesIds;
  final String? coverImageUrl;
  final bool includeINatPhotos;
  final bool includeCommonNames;
  final List<String> unresolvedSpeciesNames;
  final List<String> stillUnresolvedNames;
  final Map<String, List<String>> remainingSpeciesIdsByStage;
  final Map<String, List<String>> remainingTaxonomyEntityKeysByStage;
  final bool hasAnyImage;

  const EnrichmentJobPayload({
    this.speciesIds = const [],
    this.coverImageUrl,
    this.includeINatPhotos = true,
    this.includeCommonNames = true,
    this.unresolvedSpeciesNames = const [],
    this.stillUnresolvedNames = const [],
    this.remainingSpeciesIdsByStage = const {},
    this.remainingTaxonomyEntityKeysByStage = const {},
    this.hasAnyImage = false,
  });

  Map<String, dynamic> toJson() => {
    'speciesIds': speciesIds,
    'coverImageUrl': coverImageUrl,
    'includeINatPhotos': includeINatPhotos,
    'includeCommonNames': includeCommonNames,
    'unresolvedSpeciesNames': unresolvedSpeciesNames,
    'stillUnresolvedNames': stillUnresolvedNames,
    'remainingSpeciesIdsByStage': remainingSpeciesIdsByStage,
    'remainingTaxonomyEntityKeysByStage': remainingTaxonomyEntityKeysByStage,
    'hasAnyImage': hasAnyImage,
  };

  factory EnrichmentJobPayload.fromJson(Map<String, dynamic> json) {
    return EnrichmentJobPayload(
      speciesIds: (json['speciesIds'] as List<dynamic>? ?? const [])
          .cast<String>(),
      coverImageUrl: json['coverImageUrl'] as String?,
      includeINatPhotos: json['includeINatPhotos'] as bool? ?? true,
      includeCommonNames: json['includeCommonNames'] as bool? ?? true,
      unresolvedSpeciesNames:
          (json['unresolvedSpeciesNames'] as List<dynamic>? ?? const [])
              .cast<String>(),
      stillUnresolvedNames:
          (json['stillUnresolvedNames'] as List<dynamic>? ?? const [])
              .cast<String>(),
      remainingSpeciesIdsByStage: {
        for (final entry
            in (json['remainingSpeciesIdsByStage'] as Map<String, dynamic>? ??
                    const <String, dynamic>{})
                .entries)
          entry.key: (entry.value as List<dynamic>? ?? const []).cast<String>(),
      },
      remainingTaxonomyEntityKeysByStage: {
        for (final entry
            in (json['remainingTaxonomyEntityKeysByStage']
                        as Map<String, dynamic>? ??
                    const <String, dynamic>{})
                .entries)
          entry.key: (entry.value as List<dynamic>? ?? const []).cast<String>(),
      },
      hasAnyImage: json['hasAnyImage'] as bool? ?? false,
    );
  }

  EnrichmentJobPayload copyWith({
    List<String>? speciesIds,
    String? coverImageUrl,
    bool? includeINatPhotos,
    bool? includeCommonNames,
    List<String>? unresolvedSpeciesNames,
    List<String>? stillUnresolvedNames,
    Map<String, List<String>>? remainingSpeciesIdsByStage,
    Map<String, List<String>>? remainingTaxonomyEntityKeysByStage,
    bool? hasAnyImage,
  }) {
    return EnrichmentJobPayload(
      speciesIds: speciesIds ?? this.speciesIds,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      includeINatPhotos: includeINatPhotos ?? this.includeINatPhotos,
      includeCommonNames: includeCommonNames ?? this.includeCommonNames,
      unresolvedSpeciesNames:
          unresolvedSpeciesNames ?? this.unresolvedSpeciesNames,
      stillUnresolvedNames: stillUnresolvedNames ?? this.stillUnresolvedNames,
      remainingSpeciesIdsByStage:
          remainingSpeciesIdsByStage ?? this.remainingSpeciesIdsByStage,
      remainingTaxonomyEntityKeysByStage:
          remainingTaxonomyEntityKeysByStage ??
          this.remainingTaxonomyEntityKeysByStage,
      hasAnyImage: hasAnyImage ?? this.hasAnyImage,
    );
  }

  List<String>? remainingSpeciesIdsForStage(EnrichmentStage stage) {
    return remainingSpeciesIdsByStage[stage.name];
  }

  List<String>? remainingTaxonomyEntityKeysForStage(EnrichmentStage stage) {
    return remainingTaxonomyEntityKeysByStage[stage.name];
  }

  EnrichmentJobPayload copyWithRemainingSpeciesIds(
    EnrichmentStage stage,
    Iterable<String>? speciesIds,
  ) {
    final next = Map<String, List<String>>.from(remainingSpeciesIdsByStage);
    if (speciesIds == null) {
      next.remove(stage.name);
    } else {
      next[stage.name] = speciesIds.toList();
    }
    return copyWith(remainingSpeciesIdsByStage: next);
  }

  EnrichmentJobPayload copyWithRemainingTaxonomyEntityKeys(
    EnrichmentStage stage,
    Iterable<String>? entityKeys,
  ) {
    final next = Map<String, List<String>>.from(
      remainingTaxonomyEntityKeysByStage,
    );
    if (entityKeys == null) {
      next.remove(stage.name);
    } else {
      next[stage.name] = entityKeys.toList();
    }
    return copyWith(remainingTaxonomyEntityKeysByStage: next);
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

  /// True once both image-loading stages (`base` and `inatPrimary`) have
  /// reached a terminal-success state (`succeeded` or `skipped`) for every
  /// species. From this point on the deck has at least one image — or an
  /// explicit no-result marker — for every card and is learnable.
  bool get everySpeciesHasImage {
    bool isFinal(EnrichmentStageState? state) =>
        state == EnrichmentStageState.succeeded ||
        state == EnrichmentStageState.skipped;
    return isFinal(stageStates[EnrichmentStage.base]) &&
        isFinal(stageStates[EnrichmentStage.inatPrimary]);
  }
}
