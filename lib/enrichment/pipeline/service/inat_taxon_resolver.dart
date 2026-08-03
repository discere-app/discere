import 'package:discere/catalog/model/external_id_provider.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/repository/external_id_cache_repository.dart';
import 'package:discere/catalog/repository/external_id_repository.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/shared/util/logger.dart';

/// Resolves a species' iNaturalist taxon ID — from the reference DB or the
/// runtime cache if already known, otherwise via a scientific-name search
/// fallback — and persists newly-discovered IDs back into the cache.
///
/// Split out of `EnrichmentService` because every species-level capability
/// (`BaseImageEnrichmentService` doesn't need this, but
/// `INatPhotoEnrichmentService` and `SpeciesCommonNameEnrichmentService`
/// both do) needs the exact same taxon-resolution logic, and duplicating it
/// per service would risk the two drifting apart.
class INatTaxonResolver {
  static final _log = Logger.forType(INatTaxonResolver);

  final SpeciesRepository _speciesRepository;
  final ExternalIdRepository _externalIdRepository;
  final ExternalIdCacheRepository _externalIdCacheRepository;

  const INatTaxonResolver(
    this._speciesRepository,
    this._externalIdRepository,
    this._externalIdCacheRepository,
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
  /// preferred binomial name if the repository has no alternatives.
  Future<List<String>> scientificNameCandidates(Species species) async {
    final candidates = await _speciesRepository.getScientificNameCandidates(
      species.id,
      preferredScientificName: species.getBinomialName(),
    );
    if (candidates.isNotEmpty) {
      return candidates;
    }
    return [species.getBinomialName()];
  }
}
