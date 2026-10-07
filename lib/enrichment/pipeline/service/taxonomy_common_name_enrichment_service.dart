import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/taxon_rank.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/enrichment/pipeline/model/enrichment_work_plan.dart';
import 'package:discere/enrichment/pipeline/model/import_enrichment_summary.dart';
import 'package:discere/enrichment/pipeline/repository/runtime_common_name_repository.dart';
import 'package:discere/enrichment/pipeline/service/higher_taxon_id_resolver.dart';
import 'package:discere/enrichment/pipeline/service/taxonomy_work_planner.dart';
import 'package:discere/enrichment/util/ordered_unique_strings.dart';
import 'package:discere/external/inaturalist/inat_common_name_api.dart';
import 'package:discere/external/inaturalist/models/inat_common_name.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/util/concurrency_utils.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:http/http.dart' as http;

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
/// A sibling of the species-level enrichment services (photos and species
/// common names): the two share little beyond reading species rows to derive
/// their respective work items, and keeping taxonomy enrichment as its own
/// class keeps each independently small and testable.
class TaxonomyCommonNameEnrichmentService {
  static final _log = Logger.forType(TaxonomyCommonNameEnrichmentService);
  static const _maxConcurrentINatSpeciesFetches = 3;

  final SpeciesRepository _speciesRepository;
  final INatCommonNameApi _iNatNames;
  final HigherTaxonIdResolver _taxonIds;
  final RuntimeCommonNameRepository _runtimeCommonNameRepository;
  static const TaxonomyWorkPlanner _planner = TaxonomyWorkPlanner();

  const TaxonomyCommonNameEnrichmentService(
    this._speciesRepository,
    this._iNatNames,
    this._taxonIds,
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

    // What to fetch and in which order follows from the species alone; only
    // the work key needs a lookup, so that is all this adds.
    final items = <TaxonomyWorkPlanItem>[];
    for (final entry in _planner.plan(speciesList)) {
      items.add(
        TaxonomyWorkPlanItem(
          workKey: await _taxonomyWorkKey(entry),
          runtimeEntityKey: entry.runtimeEntityKey,
          rank: entry.rank,
          scientificName: entry.scientificName,
          speciesIds: entry.speciesIds,
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
    // Indexed rather than ordered here: the caller already decided which
    // entities to fetch and in which order, this only needs to look each one
    // up.
    final plan = {
      for (final entry in _planner.plan(speciesList))
        entry.runtimeEntityKey: entry,
    };
    final requestedEntityKeys = orderedUniqueStrings(
      entityKeys,
    ).where(plan.containsKey).toList(growable: false);
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
        final taxonomyTarget = plan[entityKey]!;

        try {
          final commonNames = await _fetchTaxonomyCommonNames(
            taxonomyTarget,
            speciesList,
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
          plan[entityKey]?.speciesIds ?? const {},
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

  /// Empty when iNaturalist answered conclusively: no such taxon, or one
  /// without common names. A failed request throws instead, so the caller
  /// retries rather than recording "no names" for good.
  Future<Map<String, List<INatCommonName>>> _fetchTaxonomyCommonNames(
    TaxonomyPlanEntry target,
    List<Species> speciesList,
  ) async {
    switch (await _taxonIds.resolve(target, speciesList)) {
      case HigherTaxonAbsent():
        return const {};
      case HigherTaxonFound(:final taxonId):
        final result = await _iNatNames.fetchCommonNames(
          target.scientificName,
          taxonId: taxonId,
        );
        if (result == null) {
          throw http.ClientException(
            'iNat common names for ${target.runtimeEntityKey} unavailable',
          );
        }
        return result.commonNames;
    }
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

  Future<String> _taxonomyWorkKey(TaxonomyPlanEntry entry) async {
    final taxonId = await _taxonIds.knownTaxonId(entry.runtimeEntityKey);
    return taxonId != null
        ? '${entry.rank}:taxon:$taxonId'
        : entry.runtimeEntityKey;
  }
}
