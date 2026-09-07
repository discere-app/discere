import 'package:discere/enrichment/model/deck_enrichment_projection.dart';
import 'package:discere/enrichment/model/enrichment_capability.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_tables.dart';

/// Folds the queue rows belonging to one deck into its
/// [DeckEnrichmentProjection].
///
/// Separate from the queries that produce those rows because this is where
/// the deck-facing rules actually live — when a species counts as
/// image-complete, when a base result is stale, what makes a deck report
/// pending work. Each of those is a claim about a handful of state values,
/// and reaching them through the repository would mean seeding six tables to
/// exercise one line of reasoning.
///
/// The rows keep their SQL shape rather than being mapped into models first:
/// they come from three different joins with no meaning outside this fold,
/// and three row types used in one place each would say less than the column
/// names already do.
class DeckProjectionBuilder {
  /// One row per (species, capability) pair from the deck's membership,
  /// left-joined so a species with no capability rows still appears:
  /// `species_id`, `capability`, `state`, `next_attempt_at`,
  /// `reference_db_version`, `wants_inat_photos`, `wants_common_names`.
  final List<Map<String, Object?>> speciesRows;

  /// One row per taxon referenced by the deck: `common_names_state`,
  /// `next_attempt_at`.
  final List<Map<String, Object?>> taxonomyRows;

  /// One row per name this deck could not resolve: `state`,
  /// `next_attempt_at`.
  final List<Map<String, Object?>> unresolvedNameRows;

  /// When set, a species whose `base` result was resolved against an older
  /// reference-DB version counts as stale. Null disables the check — the
  /// caller does not know the current version, so nothing can be judged
  /// against it.
  final int? currentReferenceDbVersion;

  const DeckProjectionBuilder({
    required this.speciesRows,
    required this.taxonomyRows,
    required this.unresolvedNameRows,
    this.currentReferenceDbVersion,
  });

  DeckEnrichmentProjection build(String deckId) {
    final tally = _Tally();
    final species = _foldSpeciesRows(tally);

    for (final entry in species.entries) {
      _countSpecies(entry.value, tally);
    }
    _countTaxonomy(tally);
    _countUnresolvedNames(tally);

    return DeckEnrichmentProjection(
      deckId: deckId,
      speciesCount: species.length,
      imageCompleteSpeciesCount: tally.imageComplete,
      imageDoneSpeciesCount: tally.imageDone,
      speciesCommonNamesWantedCount: tally.commonNamesWanted,
      speciesCommonNamesTerminalCount: tally.commonNamesTerminal,
      inatBackfillWantedCount: tally.backfillWanted,
      inatBackfillTerminalCount: tally.backfillTerminal,
      taxonomyTotalCount: tally.taxonomyTotal,
      taxonomyTerminalCount: tally.taxonomyTerminal,
      pendingUnresolvedNameCount: tally.pendingUnresolvedNames,
      wantsInatPhotosSpeciesCount: tally.wantsInatPhotos,
      wantsCommonNamesSpeciesCount: tally.wantsCommonNames,
      anyPermanentFailure: tally.anyPermanentFailure,
      anyImagePermanentFailure: tally.anyImagePermanentFailure,
      hasImmediatePendingWork: tally.immediatePending,
      earliestRetryAt: tally.earliestRetryAt,
      staleBaseSpeciesCount: tally.staleBase,
    );
  }

  /// Collapses the left-joined rows into one [_Species] per species id.
  Map<String, _Species> _foldSpeciesRows(_Tally tally) {
    final species = <String, _Species>{};
    for (final row in speciesRows) {
      final speciesId = row['species_id'] as String;
      final current = species.putIfAbsent(speciesId, _Species.new);

      final capability = row['capability'] as String?;
      final state = row['state'] as String?;
      if (capability != null && state != null) {
        current.states[capability] = state;
      }
      if (capability == EnrichmentCapability.base.wireName) {
        current.baseReferenceDbVersion = row['reference_db_version'] as int?;
      }
      current.wantsInatPhotos = (row['wants_inat_photos'] as int? ?? 0) == 1;
      current.wantsCommonNames = (row['wants_common_names'] as int? ?? 0) == 1;
      tally.considerPending(state, row['next_attempt_at']);
    }
    return species;
  }

  void _countSpecies(_Species species, _Tally tally) {
    final states = species.states;
    final baseState = states[EnrichmentCapability.base.wireName];
    final primaryState = states[EnrichmentCapability.inatPrimary.wireName];

    if (currentReferenceDbVersion != null &&
        resolvedStates.contains(baseState)) {
      final stored = species.baseReferenceDbVersion;
      if (stored == null || stored < currentReferenceDbVersion!) {
        tally.staleBase++;
      }
    }

    // A species is image-complete once `base` is terminal AND — only if base
    // didn't itself succeed — `inatPrimary` is also terminal. `inatPrimary`
    // is seeded reactively by BaseWorker exactly when base doesn't succeed,
    // so a species whose base succeeded never gets an inatPrimary row at all:
    // "no row" must count as complete there, not incomplete. The same holds
    // for a species without iNat-photo consent, which never gets that row
    // either — without this branch its image stage would never resolve and
    // the whole deck would sit in loadingBase forever, waiting on a request
    // that will never be made.
    if (terminalStates.contains(baseState)) {
      if (baseState == doneState ||
          terminalStates.contains(primaryState) ||
          !species.wantsInatPhotos) {
        tally.imageComplete++;
      }
    }
    if (baseState == doneState || primaryState == doneState) {
      tally.imageDone++;
    }
    if (baseState == permanentFailureState ||
        primaryState == permanentFailureState) {
      tally.anyImagePermanentFailure = true;
    }

    tally.countOptionalCapability(
      states,
      EnrichmentCapability.speciesCommonNames,
      onWanted: () => tally.commonNamesWanted++,
      onTerminal: () => tally.commonNamesTerminal++,
    );
    tally.countOptionalCapability(
      states,
      EnrichmentCapability.inatBackfill,
      onWanted: () => tally.backfillWanted++,
      onTerminal: () => tally.backfillTerminal++,
    );

    if (states.values.contains(permanentFailureState)) {
      tally.anyPermanentFailure = true;
    }
    if (species.wantsInatPhotos) tally.wantsInatPhotos++;
    if (species.wantsCommonNames) tally.wantsCommonNames++;
  }

  void _countTaxonomy(_Tally tally) {
    for (final row in taxonomyRows) {
      tally.taxonomyTotal++;
      final state = row['common_names_state'] as String?;
      if (terminalStates.contains(state)) tally.taxonomyTerminal++;
      if (state == permanentFailureState) tally.anyPermanentFailure = true;
      tally.considerPending(state, row['next_attempt_at']);
    }
  }

  void _countUnresolvedNames(_Tally tally) {
    for (final row in unresolvedNameRows) {
      final state = row['state'] as String?;
      if (state == permanentFailureState) {
        tally.anyPermanentFailure = true;
      } else {
        tally.pendingUnresolvedNames++;
      }
      tally.considerPending(state, row['next_attempt_at']);
    }
  }

}

/// One species' capability states plus the two consent flags, as they arrive
/// spread across several joined rows.
class _Species {
  final Map<String, String> states = {};
  int? baseReferenceDbVersion;
  bool wantsInatPhotos = false;
  bool wantsCommonNames = false;
}

class _Tally {
  int imageComplete = 0;
  int imageDone = 0;
  int commonNamesWanted = 0;
  int commonNamesTerminal = 0;
  int backfillWanted = 0;
  int backfillTerminal = 0;
  int taxonomyTotal = 0;
  int taxonomyTerminal = 0;
  int pendingUnresolvedNames = 0;
  int wantsInatPhotos = 0;
  int wantsCommonNames = 0;
  int staleBase = 0;
  bool anyPermanentFailure = false;
  bool anyImagePermanentFailure = false;
  bool immediatePending = false;
  DateTime? earliestRetryAt;

  /// Whether anything is runnable right now, and if not, when the earliest
  /// scheduled retry is due. Fed from all three row sets, because a deck is
  /// waiting if *any* of them is.
  void considerPending(String? state, Object? nextAttemptAtMillis) {
    if (state == pendingState || state == runningState) {
      immediatePending = true;
    }
    if (state != retryScheduledState || nextAttemptAtMillis is! int) return;
    final candidate = DateTime.fromMillisecondsSinceEpoch(nextAttemptAtMillis);
    final earliest = earliestRetryAt;
    if (earliest == null || candidate.isBefore(earliest)) {
      earliestRetryAt = candidate;
    }
  }

  /// A capability that is only present for species that actually need it —
  /// absence means "not wanted", not "not done".
  void countOptionalCapability(
    Map<String, String> states,
    EnrichmentCapability capability, {
    required void Function() onWanted,
    required void Function() onTerminal,
  }) {
    final state = states[capability.wireName];
    if (state == null) return;
    onWanted();
    if (terminalStates.contains(state)) onTerminal();
  }
}
