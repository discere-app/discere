import 'package:discere/catalog/model/external_id_provider.dart';
import 'package:discere/catalog/repository/external_id_cache_repository.dart';
import 'package:discere/catalog/repository/external_id_repository.dart';
import 'package:discere/external/inaturalist/inaturalist_service.dart';

/// Opportunistically backfills iNat taxon-detail-derived fields (Wikipedia
/// URL, IUCN status) that are missing from the external-ID cache.
///
/// Species enriched before a given field existed have a cached iNat taxon ID
/// but never had that field fetched, and the enrichment pipeline never
/// revisits species that already reached a terminal (photo-complete) state.
/// Rather than a batch backfill job, this fills the gap lazily wherever the
/// data is actually shown: on a cache miss it resolves the already-known
/// taxon ID and fetches the taxon detail once, caching whichever of the two
/// fields come back so future lookups (from any consumer) hit the cache.
class SpeciesInatMetadataService {
  final INaturalistService _iNatService;
  final ExternalIdRepository _externalIdRepository;
  final ExternalIdCacheRepository _externalIdCacheRepository;

  SpeciesInatMetadataService(
    this._iNatService, {
    ExternalIdRepository? externalIdRepository,
    ExternalIdCacheRepository? externalIdCacheRepository,
  }) : _externalIdRepository = externalIdRepository ?? ExternalIdRepository(),
       _externalIdCacheRepository =
           externalIdCacheRepository ?? ExternalIdCacheRepository();

  /// Returns the cached value for [provider] on [speciesId], backfilling it
  /// (and its sibling field) from iNaturalist first if it's missing but the
  /// species' taxon ID is already known. Returns null if there's nothing
  /// cached and nothing to backfill (unknown taxon, or iNat has neither
  /// field on file).
  Future<String?> ensureCached(
    String speciesId,
    ExternalIdProvider provider,
  ) async {
    final cached = await _externalIdCacheRepository.getExternalId(
      speciesId,
      provider,
    );
    if (cached != null && cached.isNotEmpty) return cached;

    final taxonId = await _resolveTaxonId(speciesId);
    if (taxonId == null) return null;

    final metadata = await _iNatService.fetchTaxonMetadata(taxonId);
    if (metadata == null) return null;

    final wikipediaUrl = metadata.wikipediaUrl;
    if (wikipediaUrl != null && wikipediaUrl.isNotEmpty) {
      await _externalIdCacheRepository.saveExternalId(
        speciesId,
        ExternalIdProvider.wikipedia,
        wikipediaUrl,
      );
    }
    final iucnStatus = metadata.iucnStatus;
    if (iucnStatus != null && iucnStatus.isNotEmpty) {
      await _externalIdCacheRepository.saveExternalId(
        speciesId,
        ExternalIdProvider.iucnStatus,
        iucnStatus,
      );
    }

    switch (provider) {
      case ExternalIdProvider.wikipedia:
        return wikipediaUrl;
      case ExternalIdProvider.iucnStatus:
        return iucnStatus;
      case ExternalIdProvider.inaturalist:
        return null;
    }
  }

  Future<int?> _resolveTaxonId(String speciesId) async {
    final referenceId = await _externalIdRepository.getExternalId(
      speciesId,
      ExternalIdProvider.inaturalist,
    );
    final referenceTaxonId = referenceId != null
        ? int.tryParse(referenceId)
        : null;
    if (referenceTaxonId != null) return referenceTaxonId;

    final cachedId = await _externalIdCacheRepository.getExternalId(
      speciesId,
      ExternalIdProvider.inaturalist,
    );
    return cachedId != null ? int.tryParse(cachedId) : null;
  }
}
