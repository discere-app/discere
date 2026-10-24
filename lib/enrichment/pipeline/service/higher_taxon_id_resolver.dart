import 'package:discere/catalog/model/external_id_provider.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/taxon_rank.dart';
import 'package:discere/catalog/repository/external_id_cache_repository.dart';
import 'package:discere/catalog/repository/external_id_rejection_repository.dart';
import 'package:discere/catalog/repository/external_id_repository.dart';
import 'package:discere/catalog/repository/inat_allowed_ancestor_repository.dart';
import 'package:discere/enrichment/pipeline/service/inat_taxon_resolver.dart';
import 'package:discere/enrichment/pipeline/service/taxonomy_work_planner.dart';
import 'package:discere/external/inaturalist/inat_taxon_detail_reader.dart';
import 'package:discere/external/inaturalist/inat_taxon_details.dart';
import 'package:discere/external/inaturalist/inat_taxon_id_resolver.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:http/http.dart' as http;

/// How looking up a higher taxon on iNaturalist ended, when iNaturalist
/// answered at all — a failed request throws instead.
sealed class HigherTaxonResolution {
  const HigherTaxonResolution();
}

/// iNaturalist knows the taxon under [taxonId].
final class HigherTaxonFound extends HigherTaxonResolution {
  final int taxonId;

  const HigherTaxonFound(this.taxonId);
}

/// No iNaturalist taxon may be taken for it: the ETL rejected the taxa of
/// its name, or no sampled species' ancestry names it and no single taxon
/// that fits carries exactly its name on its rank.
final class HigherTaxonAbsent extends HigherTaxonResolution {
  const HigherTaxonAbsent();
}

/// Finds the iNaturalist taxon id of a genus, family, order or class.
///
/// In order: the reference database, an id found earlier and cached, the
/// ancestry of the taxon's own species, and last an exact name search. A
/// name key the ETL rejected — it stands for taxa of several phyla or
/// classes, or iNaturalist's taxon of that name did not fit — gets neither
/// of the last two: whatever they found would be wrong for at least one row
/// the key stands for. The ancestry comes before the search because it
/// proves identity: a name in the chain of a species the reference data
/// files under this taxon is this taxon, whatever rank iNaturalist gives it,
/// and a homonym elsewhere in the tree (Articulata: a brachiopod class here,
/// a crinoid subclass there) cannot match. The search catches what is left —
/// taxa iNaturalist has, but under which it files none of the sampled
/// species — and takes a hit only under a phylum and class that fit every
/// row the key stands for.
///
/// Species are resolved by [INatTaxonIdResolver.resolve] instead, which
/// accepts a synonym hit — exactly what this must not.
class HigherTaxonIdResolver {
  static final _log = Logger.forType(HigherTaxonIdResolver);

  /// One batched detail request's worth. A name that sits in no chain at
  /// all (Teleostei, which iNaturalist does not have) would otherwise cost
  /// a request per thirty species on every attempt, and species of one
  /// taxon rarely disagree on their ancestry beyond thirty of them.
  static const _maxAncestrySpecies = 30;

  final ExternalIdRepository _externalIdRepository;
  final ExternalIdCacheRepository _externalIdCacheRepository;
  final ExternalIdRejectionRepository _rejections;
  final INatAllowedAncestorRepository _allowedAncestors;
  final INatTaxonResolver _speciesTaxonIds;
  final INatTaxonDetails _taxonDetails;
  final INatTaxonIdResolver _taxonIds;

  const HigherTaxonIdResolver(
    this._externalIdRepository,
    this._externalIdCacheRepository,
    this._rejections,
    this._allowedAncestors,
    this._speciesTaxonIds,
    this._taxonDetails,
    this._taxonIds,
  );

  /// The id on record for [entityKey] without asking iNaturalist: the
  /// reference database's, else one found earlier. Null when neither has
  /// one.
  Future<int?> knownTaxonId(String entityKey) async {
    final referenceId = await _externalIdRepository.getExternalId(
      entityKey,
      ExternalIdProvider.inaturalist,
    );
    final taxonId = referenceId != null ? int.tryParse(referenceId) : null;
    if (taxonId != null) return taxonId;

    final cachedId = await _externalIdCacheRepository.getExternalId(
      entityKey,
      ExternalIdProvider.inaturalist,
    );
    return cachedId != null ? int.tryParse(cachedId) : null;
  }

  /// Resolves [target], reading the ancestry of those of [speciesList] that
  /// sit under it. A newly found id is cached under the target's entity key,
  /// so the next lookup — and the work key — finds it in [knownTaxonId].
  Future<HigherTaxonResolution> resolve(
    TaxonomyPlanEntry target,
    List<Species> speciesList,
  ) async {
    final knownId = await knownTaxonId(target.runtimeEntityKey);
    if (knownId != null) return HigherTaxonFound(knownId);
    if (await _rejections.isRejected(
      target.runtimeEntityKey,
      ExternalIdProvider.inaturalist,
    )) {
      _log.debug('No iNat lookup for ${target.runtimeEntityKey}: rejected');
      return const HigherTaxonAbsent();
    }

    final foundId =
        await _idFromAncestry(target, speciesList) ??
        await _idFromExactSearch(target);
    if (foundId == null) return const HigherTaxonAbsent();

    await _externalIdCacheRepository.saveExternalId(
      target.runtimeEntityKey,
      ExternalIdProvider.inaturalist,
      foundId.toString(),
    );
    _log.debug('Resolved ${target.runtimeEntityKey} to iNat taxon $foundId');
    return HigherTaxonFound(foundId);
  }

  /// The id the first sampled species' ancestry names [target] with. Only
  /// species with a known iNaturalist id can be sampled; sorted, so the same
  /// deck samples the same species every time.
  Future<int?> _idFromAncestry(
    TaxonomyPlanEntry target,
    List<Species> speciesList,
  ) async {
    final knownSpeciesTaxonIds = await _speciesTaxonIds
        .batchResolveKnownTaxonIds([
          for (final species in speciesList)
            if (target.speciesIds.contains(species.id)) species,
        ]);
    final sampledSpeciesIds = knownSpeciesTaxonIds.keys.toList()..sort();
    final sampledTaxonIds = [
      for (final speciesId in sampledSpeciesIds.take(_maxAncestrySpecies))
        knownSpeciesTaxonIds[speciesId]!,
    ];

    await _taxonDetails.prefetch(sampledTaxonIds);
    for (final speciesTaxonId in sampledTaxonIds) {
      final detail = await _taxonDetails.fetch(speciesTaxonId);
      if (detail.retryableFailure) {
        throw http.ClientException(
          'iNat taxon detail for $speciesTaxonId unavailable',
        );
      }
      final ancestorId = ancestorIdNamed(
        detail.taxonDetail,
        scientificName: target.scientificName,
        rank: target.rank,
      );
      if (ancestorId != null) return ancestorId;
    }
    return null;
  }

  /// Null as well when the reference database can say which phyla fit, but
  /// not for every row the name key stands for: nothing to tell a homonym
  /// apart by.
  Future<int?> _idFromExactSearch(TaxonomyPlanEntry target) async {
    final rank = TaxonRank.fromRankName(target.rank);
    if (rank == null) return null;
    final ancestry = await _allowedAncestors.requirementForHigherTaxon(
      rank,
      target.scientificName,
    );
    if (ancestry != null && !ancestry.canBeMet) return null;
    try {
      return await _taxonIds.resolveExact(
        target.scientificName,
        rank: target.rank,
        ancestry: ancestry,
      );
    } on TaxonNotFoundException {
      return null;
    }
  }
}
