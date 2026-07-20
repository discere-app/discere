import 'package:discere/catalog/model/external_id_provider.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/taxon_rank.dart';
import 'package:discere/catalog/repository/external_id_cache_repository.dart';
import 'package:discere/catalog/repository/external_id_repository.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/enrichment/model/enrichment_work_plan.dart';
import 'package:discere/enrichment/repository/runtime_common_name_repository.dart';
import 'package:discere/enrichment/service/enrichment_service.dart';
import 'package:discere/enrichment/util/ordered_unique_strings.dart';
import 'package:discere/external/inaturalist/inaturalist_service.dart';
import 'package:discere/external/inaturalist/models/inat_common_name.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/util/concurrency_utils.dart';
import 'package:discere/shared/util/logger.dart';

class TaxonomyCommonNameDiagnostics {
  final Set<String> failedEntityKeys;
  final Set<String> speciesIdsWithRemainingErrors;

  const TaxonomyCommonNameDiagnostics({
    this.failedEntityKeys = const <String>{},
    this.speciesIdsWithRemainingErrors = const <String>{},
  });
}

/// Fetches and caches multilingual common names for higher taxonomy ranks
/// (genus/family/order/class) from iNaturalist.
///
/// Split out from [EnrichmentService], which owns species-level enrichment
/// (photos and species common names) — the two share little beyond reading
/// species rows to derive their respective work items, and having taxonomy
/// enrichment as its own class keeps each independently small and testable.
class TaxonomyCommonNameEnrichmentService {
  static final _log = Logger.forType(TaxonomyCommonNameEnrichmentService);
  static const _maxConcurrentINatSpeciesFetches = 3;

  final SpeciesRepository _speciesRepository;
  final INaturalistService _iNatService;
  final ExternalIdRepository _externalIdRepository;
  final ExternalIdCacheRepository _externalIdCacheRepository;
  final RuntimeCommonNameRepository _runtimeCommonNameRepository;

  const TaxonomyCommonNameEnrichmentService(
    this._speciesRepository,
    this._iNatService,
    this._externalIdRepository,
    this._externalIdCacheRepository,
    this._runtimeCommonNameRepository,
  );

  Future<ImportEnrichmentSummary> fetchINatTaxonomyCommonNamesForSpecies(
    Set<String> speciesIds, {
    void Function(TaxonomyCommonNameDiagnostics diagnostics)? onDiagnostics,
    bool force = false,
    int maxConcurrent = _maxConcurrentINatSpeciesFetches,
    Duration? requestSpacing,
    bool Function()? isCancelled,
  }) async {
    if (speciesIds.isEmpty) {
      return ImportEnrichmentSummary.empty;
    }
    final workPlan = await buildTaxonomyWorkPlanForSpecies(speciesIds);
    return fetchINatTaxonomyCommonNamesForEntityKeys(
      speciesIds,
      entityKeys: workPlan.map((item) => item.runtimeEntityKey),
      force: force,
      maxConcurrent: maxConcurrent,
      requestSpacing: requestSpacing,
      isCancelled: isCancelled,
      onDiagnostics: onDiagnostics,
    );
  }

  Future<List<TaxonomyWorkPlanItem>> buildTaxonomyWorkPlanForSpecies(
    Set<String> speciesIds,
  ) async {
    if (speciesIds.isEmpty) {
      return const <TaxonomyWorkPlanItem>[];
    }
    final speciesList = (await _speciesRepository.getSpecies(
      speciesIds,
    )).toList();
    final taxonomyTargets = _buildTaxonomyTargets(speciesList);
    final taxonomySpeciesMembership = _buildTaxonomySpeciesMembership(
      speciesList,
    );
    final runtimeEntityKeys = _sortedTaxonomyEntityKeysForSpecies(speciesList);
    final items = <TaxonomyWorkPlanItem>[];
    for (final runtimeEntityKey in runtimeEntityKeys) {
      final target = taxonomyTargets[runtimeEntityKey];
      if (target == null) {
        continue;
      }
      final workKey = await _taxonomyWorkKey(
        runtimeEntityKey: runtimeEntityKey,
        rank: target.rank,
      );
      items.add(
        TaxonomyWorkPlanItem(
          workKey: workKey,
          runtimeEntityKey: runtimeEntityKey,
          rank: target.rank,
          scientificName: target.scientificName,
          speciesIds:
              taxonomySpeciesMembership[runtimeEntityKey] ?? const <String>{},
        ),
      );
    }
    return items;
  }

  Future<ImportEnrichmentSummary> fetchINatTaxonomyCommonNamesForEntityKeys(
    Set<String> speciesIds, {
    required Iterable<String> entityKeys,
    void Function(String entityKey)? onEntityCompleted,
    void Function(TaxonomyCommonNameDiagnostics diagnostics)? onDiagnostics,
    bool force = false,
    int maxConcurrent = _maxConcurrentINatSpeciesFetches,
    Duration? requestSpacing,
    bool Function()? isCancelled,
  }) async {
    if (speciesIds.isEmpty) {
      return ImportEnrichmentSummary.empty;
    }

    final speciesList = (await _speciesRepository.getSpecies(
      speciesIds,
    )).toList();
    final taxonomyTargets = _buildTaxonomyTargets(speciesList);
    final taxonomySpeciesMembership = _buildTaxonomySpeciesMembership(
      speciesList,
    );
    final requestedEntityKeys = orderedUniqueStrings(
      entityKeys,
    ).where(taxonomyTargets.containsKey).toList(growable: false);
    if (requestedEntityKeys.isEmpty) {
      onDiagnostics?.call(const TaxonomyCommonNameDiagnostics());
      return ImportEnrichmentSummary.empty;
    }

    final entitiesWithNames = await _runtimeCommonNameRepository
        .getEntitiesWithStoredOutcome(requestedEntityKeys.toSet());

    // Same reasoning as EnrichmentService.fetchSpeciesCommonNamesForSpecies:
    // entities that already have stored common names must be excluded from
    // the throttled candidate list up front, not skipped inside the task,
    // otherwise runThrottled still burns a full requestSpacing delay on each
    // of them.
    final candidateEntityKeys = <String>[];
    final terminalEntityKeys = <String>[];
    for (final entityKey in requestedEntityKeys) {
      if (!force && entitiesWithNames.contains(entityKey)) {
        terminalEntityKeys.add(entityKey);
      } else {
        candidateEntityKeys.add(entityKey);
      }
    }

    var enrichedEntityCount = 0;
    var commonNameCount = 0;
    final pendingTaxonomyCommonNames = <RuntimeTaxonomyCommonNameRecord>[];
    final failedEntityKeys = <String>{};

    for (final entityKey in terminalEntityKeys) {
      onEntityCompleted?.call(entityKey);
    }

    await runThrottled<String>(
      candidateEntityKeys,
      maxConcurrent: maxConcurrent,
      requestSpacing: requestSpacing,
      isCancelled: isCancelled,
      task: (entityKey) async {
        final taxonomyTarget = taxonomyTargets[entityKey]!;

        try {
          final commonNames = await _fetchTaxonomyCommonNames(
            entityKey: entityKey,
            scientificName: taxonomyTarget.scientificName,
            rank: taxonomyTarget.rank,
          );
          if (commonNames.isEmpty) {
            await _runtimeCommonNameRepository.markNoCommonNames(
              entityKey: entityKey,
              entityType: _entityTypeForTaxonomyRank(taxonomyTarget.rank),
            );
            onEntityCompleted?.call(entityKey);
            return;
          }

          pendingTaxonomyCommonNames.add(
            RuntimeTaxonomyCommonNameRecord(
              entityKey: entityKey,
              entityId: taxonomyTarget.entityId,
              entityType: _entityTypeForTaxonomyRank(taxonomyTarget.rank),
              scientificName: taxonomyTarget.scientificName,
              referenceCommonNames: _referenceCommonNamesForTaxonomyTarget(
                speciesList,
                taxonomyTarget.rank,
                taxonomyTarget.scientificName,
              ),
              runtimeCommonNames: commonNames,
            ),
          );
          enrichedEntityCount++;
          commonNameCount += commonNames.values.fold(
            0,
            (sum, list) => sum + list.length,
          );
          onEntityCompleted?.call(entityKey);
        } catch (e) {
          failedEntityKeys.add(entityKey);
          _log.warn(
            'iNat taxonomy common-name fetch failed for $entityKey: $e',
          );
        }
      },
    );

    await _runtimeCommonNameRepository.saveTaxonomyCommonNamesBatch(
      pendingTaxonomyCommonNames,
    );
    if (onDiagnostics != null) {
      final failedSpeciesIds = <String>{};
      for (final entityKey in failedEntityKeys) {
        failedSpeciesIds.addAll(
          taxonomySpeciesMembership[entityKey] ?? const {},
        );
      }
      onDiagnostics(
        TaxonomyCommonNameDiagnostics(
          failedEntityKeys: failedEntityKeys,
          speciesIdsWithRemainingErrors: failedSpeciesIds,
        ),
      );
    }

    return ImportEnrichmentSummary(
      imageSpeciesCount: 0,
      imageCount: 0,
      commonNameSpeciesCount: enrichedEntityCount,
      commonNameCount: commonNameCount,
    );
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<Map<String, List<INatCommonName>>> _fetchTaxonomyCommonNames({
    required String entityKey,
    required String scientificName,
    required String rank,
  }) async {
    final referenceId = await _externalIdRepository.getExternalId(
      entityKey,
      ExternalIdProvider.inaturalist,
    );
    var taxonId = referenceId != null ? int.tryParse(referenceId) : null;
    if (taxonId == null) {
      final savedId = await _externalIdCacheRepository.getExternalId(
        entityKey,
        ExternalIdProvider.inaturalist,
      );
      taxonId = savedId != null ? int.tryParse(savedId) : null;
    }

    final ({int taxonId, Map<String, List<INatCommonName>> commonNames})?
    result;
    try {
      result = await _iNatService.fetchCommonNames(
        scientificName,
        taxonId: taxonId,
        rank: rank,
      );
    } on TaxonNotFoundException {
      // Confirmed unresolvable, same terminal outcome as an empty result.
      return const {};
    }
    if (result == null || result.commonNames.isEmpty) return const {};

    if (taxonId == null) {
      await _externalIdCacheRepository.saveExternalId(
        entityKey,
        ExternalIdProvider.inaturalist,
        result.taxonId.toString(),
      );
    }

    return result.commonNames;
  }

  Map<String, ({String rank, String scientificName, String? entityId})>
  _buildTaxonomyTargets(List<Species> speciesList) {
    final taxonomyTargets =
        <String, ({String rank, String scientificName, String? entityId})>{};

    for (final species in speciesList) {
      final classification = species.classification;
      _registerTaxonomyTarget(
        taxonomyTargets,
        rank: TaxonRank.genus,
        scientificName: classification.genusScientificName,
        entityId: classification.genusId,
      );
      _registerTaxonomyTarget(
        taxonomyTargets,
        rank: TaxonRank.family,
        scientificName: classification.familyScientificName,
        entityId: classification.familyId,
      );
      _registerTaxonomyTarget(
        taxonomyTargets,
        rank: TaxonRank.order,
        scientificName: classification.orderScientificName,
        entityId: classification.orderId,
      );
      _registerTaxonomyTarget(
        taxonomyTargets,
        rank: TaxonRank.classRank,
        scientificName: classification.classScientificName,
        entityId: classification.classId,
      );
    }

    return taxonomyTargets;
  }

  Map<String, Set<String>> _buildTaxonomySpeciesMembership(
    List<Species> speciesList,
  ) {
    final membership = <String, Set<String>>{};

    for (final species in speciesList) {
      final classification = species.classification;
      void addMember(TaxonRank rank, String scientificName) {
        membership
            .putIfAbsent(rank.entityKey(scientificName), () => <String>{})
            .add(species.id);
      }

      addMember(TaxonRank.genus, classification.genusScientificName);
      addMember(TaxonRank.family, classification.familyScientificName);
      addMember(TaxonRank.order, classification.orderScientificName);
      addMember(TaxonRank.classRank, classification.classScientificName);
    }

    return membership;
  }

  List<String> _sortedTaxonomyEntityKeysForSpecies(List<Species> speciesList) {
    final taxonomySpeciesMembership = _buildTaxonomySpeciesMembership(
      speciesList,
    );
    final entityKeys = taxonomySpeciesMembership.keys.toList(growable: false);
    entityKeys.sort((left, right) {
      final leftCount = taxonomySpeciesMembership[left]?.length ?? 0;
      final rightCount = taxonomySpeciesMembership[right]?.length ?? 0;
      final countComparison = rightCount.compareTo(leftCount);
      if (countComparison != 0) {
        return countComparison;
      }
      return left.compareTo(right);
    });
    return entityKeys;
  }

  void _registerTaxonomyTarget(
    Map<String, ({String rank, String scientificName, String? entityId})>
    taxonomyTargets, {
    required TaxonRank rank,
    required String scientificName,
    required String? entityId,
  }) {
    taxonomyTargets[rank.entityKey(scientificName)] = (
      rank: rank.rankName,
      scientificName: scientificName,
      entityId: entityId,
    );
  }

  Map<Language, List<String>> _referenceCommonNamesForTaxonomyTarget(
    List<Species> speciesList,
    String rank,
    String scientificName,
  ) {
    final taxonRank = TaxonRank.fromRankName(rank);
    for (final species in speciesList) {
      final classification = species.classification;
      switch (taxonRank) {
        case TaxonRank.genus:
          if (classification.genusScientificName == scientificName) {
            return classification.genusCommonNames;
          }
          break;
        case TaxonRank.family:
          if (classification.familyScientificName == scientificName) {
            return classification.familyCommonNames;
          }
          break;
        case TaxonRank.order:
          if (classification.orderScientificName == scientificName) {
            return classification.orderCommonNames;
          }
          break;
        case TaxonRank.classRank:
          if (classification.classScientificName == scientificName) {
            return classification.classCommonNames;
          }
          break;
        case null:
          break;
      }
    }

    return const {};
  }

  String _entityTypeForTaxonomyRank(String rank) =>
      TaxonRank.fromRankName(rank)?.entityType ?? rank;

  Future<String> _taxonomyWorkKey({
    required String runtimeEntityKey,
    required String rank,
  }) async {
    final referenceId = await _externalIdRepository.getExternalId(
      runtimeEntityKey,
      ExternalIdProvider.inaturalist,
    );
    var taxonId = referenceId != null ? int.tryParse(referenceId) : null;
    if (taxonId == null) {
      final savedId = await _externalIdCacheRepository.getExternalId(
        runtimeEntityKey,
        ExternalIdProvider.inaturalist,
      );
      taxonId = savedId != null ? int.tryParse(savedId) : null;
    }
    if (taxonId != null) {
      return '$rank:taxon:$taxonId';
    }
    return runtimeEntityKey;
  }
}
