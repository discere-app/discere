import 'package:discere/catalog/model/external_id_provider.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/repository/external_id_cache_repository.dart';
import 'package:discere/catalog/repository/external_id_rejection_repository.dart';
import 'package:discere/catalog/repository/external_id_repository.dart';
import 'package:discere/catalog/repository/inat_allowed_ancestor_repository.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/external/inaturalist/inat_taxon_id_resolver.dart';
import 'package:discere/shared/util/logger.dart';

/// Resolves a species' iNaturalist taxon ID — from the reference DB or the
/// runtime cache if already known, otherwise via a scientific-name search —
/// and persists newly-discovered IDs back into the cache.
///
/// Every species-level capability that asks iNaturalist
/// (`INatPhotoEnrichmentService`, `SpeciesCommonNameEnrichmentService`, the
/// species detail page's live photo fetch) goes through here, so the rules
/// for when a search may assign an id exist once.
class INatTaxonResolver {
  static final _log = Logger.forType(INatTaxonResolver);

  final SpeciesRepository _speciesRepository;
  final ExternalIdRepository _externalIdRepository;
  final ExternalIdCacheRepository _externalIdCacheRepository;
  final ExternalIdRejectionRepository _rejections;
  final INatAllowedAncestorRepository _allowedAncestors;
  final INatTaxonIdResolver _taxonIds;

  const INatTaxonResolver(
    this._speciesRepository,
    this._externalIdRepository,
    this._externalIdCacheRepository,
    this._rejections,
    this._allowedAncestors,
    this._taxonIds,
  );

  /// Batch-reads known iNat taxon IDs for [speciesList] in two queries:
  /// one against the reference DB and one against the user cache for misses.
  /// Reference-DB entries take precedence over cached ones.
  Future<Map<String, int>> batchResolveKnownTaxonIds(
    List<Species> speciesList,
  ) async {
    if (speciesList.isEmpty) return const {};
    final ids = speciesList.map((s) => s.id).toSet();
    final refIds = await _externalIdRepository.getExternalIdsForProvider(
      ids,
      ExternalIdProvider.inaturalist,
    );
    final missIds = ids.difference(refIds.keys.toSet());
    final cacheIds = missIds.isEmpty
        ? const <String, int>{}
        : await _externalIdCacheRepository.getExternalIdsForProvider(
            missIds,
            ExternalIdProvider.inaturalist,
          );
    return {...cacheIds, ...refIds};
  }

  /// The id on record for [species] without asking iNaturalist: the
  /// reference database's, else one found earlier. Null when neither has
  /// one.
  Future<int?> knownTaxonId(Species species) async =>
      (await batchResolveKnownTaxonIds([species]))[species.id];

  /// Searches iNaturalist by name for the taxon id of [species], which has
  /// none on record. Null when a search failed and is worth retrying.
  ///
  /// Throws [TaxonNotFoundException] when the answer is settled, which makes
  /// the species' photos and names "none from iNaturalist" for good:
  /// - the ETL rejected every taxon of the species' names — a search would
  ///   find the same ones again;
  /// - the reference database can say which phyla fit, but not for this
  ///   species (no chain up to its class, a placeholder phylum) — there is
  ///   no telling a homonym from the species;
  /// - no candidate name found a single taxon that fits.
  Future<int?> searchTaxonId(Species species) async {
    if (await _rejections.isRejected(
      species.id,
      ExternalIdProvider.inaturalist,
    )) {
      _log.debug('No iNat search for ${species.id}: rejected by the ETL');
      throw TaxonNotFoundException(species.getBinomialName());
    }
    final ancestry = await _allowedAncestors.requirementForSpecies(
      species.classification.classId,
    );
    if (ancestry != null && !ancestry.canBeMet) {
      _log.debug('No iNat search for ${species.id}: no phylum to check');
      throw TaxonNotFoundException(species.getBinomialName());
    }

    // Only settled if every candidate name was answered conclusively, as
    // opposed to a search that failed and is worth retrying.
    var allCandidatesNotFound = true;
    for (final candidate in await scientificNameCandidates(species)) {
      try {
        final taxonId = await _taxonIds.resolve(candidate, ancestry: ancestry);
        if (taxonId == null) {
          allCandidatesNotFound = false;
          continue;
        }
        if (candidate != species.getBinomialName()) {
          _log.debug(
            'iNat search matched ${species.id}: '
            '${species.getBinomialName()} -> $candidate (taxon=$taxonId)',
          );
        }
        return taxonId;
      } on TaxonNotFoundException {
        continue;
      }
    }
    if (allCandidatesNotFound) {
      throw TaxonNotFoundException(species.getBinomialName());
    }
    return null;
  }

  /// Persists a newly runtime-resolved taxon ID — a no-op if the species
  /// already had one going in, since only genuinely new resolutions need
  /// caching.
  Future<void> persistResolvedTaxonId(
    Species species, {
    required int? previousTaxonId,
    required int resolvedTaxonId,
  }) async {
    if (previousTaxonId != null) return;

    await _externalIdCacheRepository.saveExternalId(
      species.id,
      ExternalIdProvider.inaturalist,
      resolvedTaxonId.toString(),
    );
    _log.debug(
      'Stored runtime-resolved iNat external ID for '
      '${species.getBinomialName()} (${species.id}): $resolvedTaxonId',
    );
  }

  /// Scientific-name candidates to try against iNaturalist's taxon search
  /// when no taxon ID is already known, preferring the species' own
  /// preferred binomial name if the repository has no alternatives. None for
  /// a species without a binomial: its epithet alone would find whichever
  /// species shares it.
  Future<List<String>> scientificNameCandidates(Species species) async {
    final binomial = species.binomialName;
    final candidates = await _speciesRepository.getScientificNameCandidates(
      species.id,
      preferredScientificName: binomial,
    );
    if (candidates.isNotEmpty) {
      return candidates;
    }
    return [?binomial];
  }
}
