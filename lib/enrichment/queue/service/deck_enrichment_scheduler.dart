import 'package:discere/enrichment/pipeline/repository/enrichment_ownership_repository.dart';
import 'package:discere/enrichment/ports/enrichment_job_ports.dart';
import 'package:discere/enrichment/queue/repository/enrichment_job_repository.dart';
import 'package:discere/enrichment/queue/service/deck_enrichment_priority.dart';
import 'package:discere/enrichment/queue/service/enrichment_background_scheduler.dart';
import 'package:discere/shared/util/logger.dart';

/// Brings decks into the enrichment queue and takes them out again: which
/// species each deck owns, with which consent, and the deck's cover job.
///
/// Knows nothing about the runtime that drains the queue — refreshing the
/// published status and starting the runner afterwards is the caller's job.
class DeckEnrichmentScheduler {
  static final _log = Logger.forType(DeckEnrichmentScheduler);

  final EnrichmentJobRepository _jobRepository;
  final EnrichmentOwnershipRepository _ownershipRepository;
  final DeckSpeciesSnapshotPort _deckSpeciesSnapshotPort;
  final EnrichmentBackgroundScheduler _backgroundScheduler;

  const DeckEnrichmentScheduler({
    required EnrichmentJobRepository jobRepository,
    required EnrichmentOwnershipRepository ownershipRepository,
    required DeckSpeciesSnapshotPort deckSpeciesSnapshotPort,
    required EnrichmentBackgroundScheduler backgroundScheduler,
  }) : _jobRepository = jobRepository,
       _ownershipRepository = ownershipRepository,
       _deckSpeciesSnapshotPort = deckSpeciesSnapshotPort,
       _backgroundScheduler = backgroundScheduler;

  /// Schedules [deckIds] (already normalized: unique, non-empty) with the
  /// given consent.
  Future<void> schedule(
    List<String> deckIds, {
    required bool includeINatPhotos,
    required bool includeCommonNames,
    required Map<String, String?> coverImageUrlsByDeckId,
    required Map<String, List<String>> unresolvedNamesByDeckId,
  }) async {
    final snapshots = await _deckSpeciesSnapshotPort.loadSpeciesIdsByDeckId(
      deckIds.toSet(),
    );
    final speciesIdsByDeckId = <String, Set<String>>{
      for (final deckId in deckIds)
        deckId: snapshots[deckId] ?? const <String>{},
    };
    final newDeckPriorityOrder = prioritizeDecksBySharedSpecies(
      deckIds,
      speciesIdsByDeckId,
    );

    // Include already-tracked decks at lower priority. Without this,
    // assignSpeciesOwners would re-assign overlapping species to the new
    // deck even though another deck's work for them is still in flight.
    final newDeckIdSet = deckIds.toSet();
    final existingDeckSpecies = await _ownershipRepository
        .loadAllDeckSpeciesSnapshots();
    final activeOnlyDeckIds = <String>[];
    for (final entry in existingDeckSpecies.entries) {
      if (newDeckIdSet.contains(entry.key) || entry.value.isEmpty) continue;
      speciesIdsByDeckId[entry.key] = entry.value;
      activeOnlyDeckIds.add(entry.key);
    }
    final prioritizedDeckIds = <String>[
      ...newDeckPriorityOrder,
      ...activeOnlyDeckIds,
    ];

    final assignedSpeciesIdsByDeckId = await _ownershipRepository
        .assignSpeciesOwners(
          speciesIdsByDeckId: speciesIdsByDeckId,
          prioritizedDeckIds: prioritizedDeckIds,
          // Every deck in prioritizedDeckIds must have an entry here, not
          // just the decks this call is actually scheduling — assignSpecies
          // Owners defaults an absent deck to "consents" (documented
          // convenience for callers that don't track consent at all), which
          // would silently grant iNat consent on behalf of a carried-forward
          // activeOnlyDeckId this call knows nothing new about. Explicit
          // `false` here is safe: assignSpeciesOwners ORs it against the
          // deck's already-persisted consent, so a genuinely-consenting
          // active deck keeps its consent — this only prevents a *new*
          // upgrade this call has no business granting.
          includeInatPhotosByDeckId: {
            for (final deckId in newDeckPriorityOrder)
              deckId: includeINatPhotos,
            for (final deckId in activeOnlyDeckIds) deckId: false,
          },
          includeCommonNamesByDeckId: {
            for (final deckId in newDeckPriorityOrder)
              deckId: includeCommonNames,
            for (final deckId in activeOnlyDeckIds) deckId: false,
          },
        );

    for (final deckId in newDeckPriorityOrder) {
      final speciesIds = speciesIdsByDeckId[deckId] ?? const <String>{};
      final assignedSpeciesIds =
          assignedSpeciesIdsByDeckId[deckId] ?? const <String>[];
      _log.debug(
        'Schedule deck enrichment deck=$deckId '
        'assignedSpecies=${assignedSpeciesIds.length}/${speciesIds.length}',
      );
      await _jobRepository.scheduleDeckJob(
        deckId: deckId,
        coverImageUrl: coverImageUrlsByDeckId[deckId],
      );
      // Also for a deck without new names: consent granted now must reach
      // the names it is still resolving. Carried-forward activeOnlyDeckIds
      // are left out for the same reason as above.
      await _ownershipRepository.mergeUnresolvedNames(
        deckId,
        unresolvedNamesByDeckId[deckId] ?? const [],
        wantsInatPhotos: includeINatPhotos,
        wantsCommonNames: includeCommonNames,
      );
    }
  }

  /// Removes everything the queue holds for [deckId] — its cover job, its
  /// species ownership and any background processing scheduled for it.
  Future<void> cancel(String deckId) async {
    await _jobRepository.deleteDeckJob(deckId);
    await _ownershipRepository.releaseDeck(deckId);
    await _backgroundScheduler.cancelProcessingForDeck(deckId);
  }
}
