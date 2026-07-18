import 'package:discere/enrichment/repository/enrichment_job_repository.dart';

/// Per-stage terminal outcome for a batch of species, as reported by
/// [EnrichmentJobExecutor]'s species-stage runner. Fed into
/// [RunCompletionSummaryCollector] to build a whole-run summary once local
/// diagnostics collection is enabled.
class SpeciesStageCompletionSummary {
  final EnrichmentStage stage;
  final Set<String> plannedSpeciesIds;
  final Set<String> completedSpeciesIds;
  final Set<String> speciesIdsWithRemainingErrors;

  const SpeciesStageCompletionSummary({
    required this.stage,
    required this.plannedSpeciesIds,
    required this.completedSpeciesIds,
    required this.speciesIdsWithRemainingErrors,
  });
}

/// Accumulates [SpeciesStageCompletionSummary]s across all stages processed
/// during one [EnrichmentJobExecutor.processUntilIdle] run and derives an
/// aggregate [RunCompletionSummary] once the run ends. Only instantiated
/// when [LocalDiagnostics.isEnrichmentCompletionSummaryEnabled] — building
/// this bookkeeping is skippable overhead outside of diagnostics use.
class RunCompletionSummaryCollector {
  static const _requiredStages = <EnrichmentStage>{
    EnrichmentStage.base,
    EnrichmentStage.inatPrimary,
    EnrichmentStage.names,
    EnrichmentStage.inatBackfill,
  };

  final Set<String> _plannedSpeciesIds = <String>{};
  final Map<String, Set<EnrichmentStage>> _completedStagesBySpecies =
      <String, Set<EnrichmentStage>>{};
  final Map<String, Set<EnrichmentStage>> _errorStagesBySpecies =
      <String, Set<EnrichmentStage>>{};
  int _permanentFailureCount = 0;

  void recordStageOutcome(SpeciesStageCompletionSummary summary) {
    _plannedSpeciesIds.addAll(summary.plannedSpeciesIds);
    for (final speciesId in summary.plannedSpeciesIds) {
      final completedStages = _completedStagesBySpecies.putIfAbsent(
        speciesId,
        () => <EnrichmentStage>{},
      );
      if (summary.completedSpeciesIds.contains(speciesId)) {
        completedStages.add(summary.stage);
      } else {
        completedStages.remove(summary.stage);
      }

      final errorStages = _errorStagesBySpecies.putIfAbsent(
        speciesId,
        () => <EnrichmentStage>{},
      );
      if (summary.speciesIdsWithRemainingErrors.contains(speciesId)) {
        errorStages.add(summary.stage);
      } else {
        errorStages.remove(summary.stage);
      }
      if (errorStages.isEmpty) {
        _errorStagesBySpecies.remove(speciesId);
      }
    }
  }

  void recordPermanentStageFailure({
    required EnrichmentStage stage,
    required Set<String> affectedSpeciesIds,
  }) {
    if (affectedSpeciesIds.isEmpty) {
      _permanentFailureCount += 1;
      return;
    }
    _plannedSpeciesIds.addAll(affectedSpeciesIds);
    for (final speciesId in affectedSpeciesIds) {
      _errorStagesBySpecies
          .putIfAbsent(speciesId, () => <EnrichmentStage>{})
          .add(stage);
    }
    _permanentFailureCount += 1;
  }

  RunCompletionSummary finalize({required bool queueDrained}) {
    var fullyEnrichedSpeciesCount = 0;
    var remainingFailureSpeciesCount = 0;
    for (final speciesId in _plannedSpeciesIds) {
      final completedStages = _completedStagesBySpecies[speciesId] ?? const {};
      final errorStages = _errorStagesBySpecies[speciesId] ?? const {};
      final isFullyEnriched =
          completedStages.containsAll(_requiredStages) && errorStages.isEmpty;
      if (isFullyEnriched) {
        fullyEnrichedSpeciesCount += 1;
      } else {
        remainingFailureSpeciesCount += 1;
      }
    }

    final plannedSpeciesCount = _plannedSpeciesIds.length;
    final partialSpeciesCount = plannedSpeciesCount - fullyEnrichedSpeciesCount;
    final allErrorsResolved =
        queueDrained &&
        remainingFailureSpeciesCount == 0 &&
        _permanentFailureCount == 0;
    final fullyEnriched =
        queueDrained &&
        fullyEnrichedSpeciesCount == plannedSpeciesCount &&
        remainingFailureSpeciesCount == 0 &&
        _permanentFailureCount == 0;
    final status = _statusFor(
      queueDrained: queueDrained,
      fullyEnriched: fullyEnriched,
      allErrorsResolved: allErrorsResolved,
      permanentFailureCount: _permanentFailureCount,
    );

    return RunCompletionSummary(
      status: status,
      queueDrained: queueDrained,
      fullyEnriched: fullyEnriched,
      allErrorsResolved: allErrorsResolved,
      plannedSpeciesCount: plannedSpeciesCount,
      fullyEnrichedSpeciesCount: fullyEnrichedSpeciesCount,
      partialSpeciesCount: partialSpeciesCount,
      remainingFailureSpeciesCount: remainingFailureSpeciesCount,
      permanentFailureCount: _permanentFailureCount,
    );
  }

  String _statusFor({
    required bool queueDrained,
    required bool fullyEnriched,
    required bool allErrorsResolved,
    required int permanentFailureCount,
  }) {
    if (permanentFailureCount > 0) {
      return 'failed';
    }
    if (!queueDrained) {
      return 'incomplete';
    }
    if (fullyEnriched && allErrorsResolved) {
      return 'complete';
    }
    return 'complete_with_warnings';
  }
}

/// Aggregate outcome of one [EnrichmentJobExecutor.processUntilIdle] run,
/// built by [RunCompletionSummaryCollector.finalize] and logged/recorded as
/// local diagnostics.
class RunCompletionSummary {
  final String status;
  final bool queueDrained;
  final bool fullyEnriched;
  final bool allErrorsResolved;
  final int plannedSpeciesCount;
  final int fullyEnrichedSpeciesCount;
  final int partialSpeciesCount;
  final int remainingFailureSpeciesCount;
  final int permanentFailureCount;

  const RunCompletionSummary({
    required this.status,
    required this.queueDrained,
    required this.fullyEnriched,
    required this.allErrorsResolved,
    required this.plannedSpeciesCount,
    required this.fullyEnrichedSpeciesCount,
    required this.partialSpeciesCount,
    required this.remainingFailureSpeciesCount,
    required this.permanentFailureCount,
  });

  Map<String, Object?> toDetails() {
    return {
      'completionStatus': status,
      'queueDrained': queueDrained,
      'fullyEnriched': fullyEnriched,
      'allErrorsResolved': allErrorsResolved,
      'plannedSpeciesCount': plannedSpeciesCount,
      'fullyEnrichedSpeciesCount': fullyEnrichedSpeciesCount,
      'partialSpeciesCount': partialSpeciesCount,
      'remainingFailureSpeciesCount': remainingFailureSpeciesCount,
      'permanentFailureCount': permanentFailureCount,
    };
  }
}
