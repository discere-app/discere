import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/enrichment/pipeline/model/import_enrichment_summary.dart';
import 'package:discere/enrichment/pipeline/repository/runtime_common_name_repository.dart';
import 'package:discere/enrichment/pipeline/service/inat_taxon_resolver.dart';
import 'package:discere/external/inaturalist/inaturalist_service.dart';
import 'package:discere/external/inaturalist/models/inat_common_name.dart';
import 'package:discere/shared/util/concurrency_utils.dart';
import 'package:discere/shared/util/logger.dart';

/// Fetches multilingual common names for species from iNaturalist. The
/// `speciesCommonNames` capability in the producer-consumer pipeline —
/// driven exclusively by `INatWorker`, one species at a time.
class SpeciesCommonNameEnrichmentService {
  static final _log = Logger.forType(SpeciesCommonNameEnrichmentService);
  static const _maxConcurrentFetches = 3;

  final SpeciesRepository _speciesRepository;
  final INaturalistService _iNatService;
  final RuntimeCommonNameRepository _runtimeCommonNameRepository;
  final INatTaxonResolver _taxonResolver;

  const SpeciesCommonNameEnrichmentService(
    this._speciesRepository,
    this._iNatService,
    this._runtimeCommonNameRepository,
    this._taxonResolver,
  );

  /// Fetches iNaturalist common names for all given species.
  ///
  /// Common-name enrichment follows the same terminal-callback contract as
  /// photo enrichment (see `INatPhotoEnrichmentService`). A species only
  /// completes the capability once runtime common names were stored or an
  /// explicit no-result marker was written. Transient lookup failures leave
  /// the species pending so the caller can retry.
  Future<ImportEnrichmentSummary> fetchSpeciesCommonNamesForSpecies(
    Set<String> speciesIds, {
    void Function(String speciesId)? onSpeciesCompleted,
  }) async {
    if (speciesIds.isEmpty) {
      return ImportEnrichmentSummary.empty;
    }

    final speciesList = (await _speciesRepository.getSpecies(
      speciesIds,
    )).toList();
    final entitiesWithNames = await _runtimeCommonNameRepository
        .getEntitiesWithStoredOutcome(
          speciesIds.map((speciesId) => _speciesEntityKey(speciesId)).toSet(),
        );

    final candidates = <Species>[];
    final terminalSpeciesIds = <String>{};
    for (final species in speciesList) {
      if (entitiesWithNames.contains(_speciesEntityKey(species.id))) {
        terminalSpeciesIds.add(species.id);
      } else {
        candidates.add(species);
      }
    }

    final knownTaxonIds = await _taxonResolver.batchResolveKnownTaxonIds(
      candidates,
    );
    // Process species with a known taxon ID first — their common-name fetch
    // goes straight to the API without a live name-resolve round-trip.
    candidates.sort((a, b) {
      final aKnown = knownTaxonIds.containsKey(a.id) ? 0 : 1;
      final bKnown = knownTaxonIds.containsKey(b.id) ? 0 : 1;
      return aKnown.compareTo(bKnown);
    });

    var enrichedSpeciesCount = 0;
    var commonNameCount = 0;
    final pendingSpeciesCommonNames =
        <Species, Map<String, List<INatCommonName>>>{};

    for (final speciesId in terminalSpeciesIds) {
      onSpeciesCompleted?.call(speciesId);
    }

    await runConcurrently<Species>(
      candidates,
      maxConcurrent: _maxConcurrentFetches,
      task: (species) async {
        try {
          final outcome = await _fetchSpeciesCommonNames(
            species,
            taxonId: knownTaxonIds[species.id],
          );
          if (outcome.isTerminal) {
            onSpeciesCompleted?.call(species.id);
          }
          if (outcome.commonNames.isNotEmpty) {
            pendingSpeciesCommonNames[species] = outcome.commonNames;
            enrichedSpeciesCount++;
            commonNameCount += outcome.commonNames.values.fold(
              0,
              (sum, list) => sum + list.length,
            );
          }
        } catch (e) {
          _log.warn('iNat common-name fetch failed for ${species.id}: $e');
        }
      },
    );

    await _runtimeCommonNameRepository.saveSpeciesCommonNamesBatch(
      pendingSpeciesCommonNames,
    );

    return ImportEnrichmentSummary(
      imageSpeciesCount: 0,
      imageCount: 0,
      commonNameSpeciesCount: enrichedSpeciesCount,
      commonNameCount: commonNameCount,
    );
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  /// Returns whether the species reached a terminal common-name outcome.
  ///
  /// Unlike photos, runtime common names historically had no empty marker.
  /// We now persist one through [RuntimeCommonNameRepository.markNoCommonNames]
  /// so the caller can tell "looked up and empty" apart from "not processed".
  Future<_SpeciesCommonNameFetchOutcome> _fetchSpeciesCommonNames(
    Species species, {
    int? taxonId,
  }) async {
    ({int taxonId, Map<String, List<INatCommonName>> commonNames})? result;
    try {
      result = await _fetchCommonNamesWithScientificNameFallback(
        species,
        taxonId: taxonId,
      );
    } on TaxonNotFoundException {
      await _runtimeCommonNameRepository.markNoCommonNames(
        entityKey: _speciesEntityKey(species.id),
        entityType: 'species',
      );
      return const _SpeciesCommonNameFetchOutcome(
        commonNames: {},
        isTerminal: true,
      );
    }
    if (result == null) {
      return const _SpeciesCommonNameFetchOutcome(
        commonNames: {},
        isTerminal: false,
      );
    }

    await _taxonResolver.persistResolvedTaxonId(
      species,
      previousTaxonId: taxonId,
      resolvedTaxonId: result.taxonId,
    );
    if (result.commonNames.isEmpty) {
      await _runtimeCommonNameRepository.markNoCommonNames(
        entityKey: _speciesEntityKey(species.id),
        entityType: 'species',
      );
      return const _SpeciesCommonNameFetchOutcome(
        commonNames: {},
        isTerminal: true,
      );
    }
    return _SpeciesCommonNameFetchOutcome(
      commonNames: result.commonNames,
      isTerminal: true,
    );
  }

  Future<({int taxonId, Map<String, List<INatCommonName>> commonNames})?>
  _fetchCommonNamesWithScientificNameFallback(
    Species species, {
    required int? taxonId,
  }) async {
    if (taxonId != null) {
      return _iNatService.fetchCommonNames(
        species.getBinomialName(),
        taxonId: taxonId,
      );
    }

    // Only conclude the species is genuinely unresolvable (as opposed to a
    // transient failure worth retrying later) if every candidate name was
    // definitively rejected by iNaturalist rather than merely failing.
    var allCandidatesNotFound = true;
    for (final candidate in await _taxonResolver.scientificNameCandidates(
      species,
    )) {
      try {
        final result = await _iNatService.fetchCommonNames(candidate);
        if (result == null) {
          allCandidatesNotFound = false;
          continue;
        }
        if (candidate != species.getBinomialName()) {
          _log.debug(
            'iNat common-name fallback matched ${species.id}: '
            '${species.getBinomialName()} -> $candidate '
            '(taxon=${result.taxonId})',
          );
        }
        return result;
      } on TaxonNotFoundException {
        continue;
      }
    }

    if (allCandidatesNotFound) {
      throw TaxonNotFoundException(species.getBinomialName());
    }
    return null;
  }

  String _speciesEntityKey(String speciesId) {
    return 'species:$speciesId';
  }
}

class _SpeciesCommonNameFetchOutcome {
  final Map<String, List<INatCommonName>> commonNames;
  final bool isTerminal;

  const _SpeciesCommonNameFetchOutcome({
    required this.commonNames,
    required this.isTerminal,
  });
}
