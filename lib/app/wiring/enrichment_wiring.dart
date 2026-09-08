import 'package:discere/catalog/repository/external_id_cache_repository.dart';
import 'package:discere/catalog/repository/external_id_repository.dart';
import 'package:discere/catalog/repository/runtime_common_name_search_repository.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/catalog/service/local_species_image_service.dart';
import 'package:discere/enrichment/media/service/species_media_service.dart';
import 'package:discere/enrichment/media/service/species_photo_service.dart';
import 'package:discere/enrichment/pipeline/repository/deck_enrichment_projection_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_ownership_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_claim_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_maintenance_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_outcome_repository.dart';
import 'package:discere/enrichment/pipeline/repository/inat_photo_cache_repository.dart';
import 'package:discere/enrichment/pipeline/repository/runtime_common_name_repository.dart';
import 'package:discere/enrichment/pipeline/service/base_image_enrichment_service.dart';
import 'package:discere/enrichment/pipeline/service/base_worker.dart';
import 'package:discere/enrichment/pipeline/service/inat_name_resolution_service.dart';
import 'package:discere/enrichment/pipeline/service/inat_photo_enrichment_service.dart';
import 'package:discere/enrichment/pipeline/service/inat_taxon_resolver.dart';
import 'package:discere/enrichment/pipeline/service/inat_worker.dart';
import 'package:discere/enrichment/pipeline/service/species_common_name_enrichment_service.dart';
import 'package:discere/enrichment/pipeline/service/taxonomy_common_name_enrichment_service.dart';
import 'package:discere/enrichment/ports/enrichment_job_ports.dart';
import 'package:discere/enrichment/queue/repository/enrichment_job_repository.dart';
import 'package:discere/enrichment/queue/service/cover_job_runner.dart';
import 'package:discere/enrichment/queue/service/enrichment_background_scheduler.dart';
import 'package:discere/enrichment/queue/service/enrichment_health_snapshot_service.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/external/inaturalist/inaturalist_service.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/shared/service/foreground_service_keeper.dart';
import 'package:discere/shared/service/host_cooldown_tracker.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/service/network_availability.dart';
import 'package:discere/shared/util/logger.dart';

/// Builds the `enrichment` slice's services. Needs [DecksService] (from
/// `learning`) to wire [INatEnrichmentQueueService]'s ports — inverted via
/// the local adapter classes below, since `enrichment` may not import
/// `learning` directly per the module dependency matrix.
({
  SpeciesMediaService speciesMediaService,
  INatNameResolutionService nameResolutionService,
  INatEnrichmentQueueService iNatEnrichmentQueueService,
  EnrichmentHealthSnapshotService healthSnapshotService,
})
buildEnrichmentServices({
  required SpeciesRepository speciesRepository,
  required ImageService imageService,
  required INaturalistService iNatService,
  required ExternalIdRepository externalIdRepository,
  required ExternalIdCacheRepository externalIdCacheRepository,
  required LocalSpeciesImageService localSpeciesImageService,
  required DecksService deckService,
  required EnrichmentBackgroundScheduler backgroundScheduler,
  required ForegroundServiceKeeper foregroundServiceKeeper,
  required NetworkAvailability networkAvailability,
  required HostCooldownTracker hostCooldownTracker,
  required bool processEnrichmentJobs,
}) {
  final iNatCacheRepository = INatPhotoCacheRepository();
  final speciesPhotoService = SpeciesPhotoService(
    iNatCacheRepository,
    iNatService: iNatService,
    externalIdRepository: externalIdRepository,
    externalIdCacheRepository: externalIdCacheRepository,
  );
  final speciesMediaService = SpeciesMediaService(
    speciesRepository,
    speciesPhotoService,
    localSpeciesImageService,
  );
  final runtimeCommonNameRepository = RuntimeCommonNameRepository(
    searchRepository: RuntimeCommonNameSearchRepository(),
  );
  final taxonResolver = INatTaxonResolver(
    speciesRepository,
    externalIdRepository,
    externalIdCacheRepository,
  );
  final baseImageEnrichmentService = BaseImageEnrichmentService(
    speciesRepository,
    imageService,
  );
  final photoEnrichmentService = INatPhotoEnrichmentService(
    speciesRepository,
    iNatService,
    iNatCacheRepository,
    imageService,
    externalIdCacheRepository,
    taxonResolver,
  );
  final commonNameEnrichmentService = SpeciesCommonNameEnrichmentService(
    speciesRepository,
    iNatService,
    runtimeCommonNameRepository,
    taxonResolver,
  );
  final taxonomyEnrichmentService = TaxonomyCommonNameEnrichmentService(
    speciesRepository,
    iNatService,
    externalIdRepository,
    externalIdCacheRepository,
    runtimeCommonNameRepository,
  );
  final nameResolutionService = INatNameResolutionService(
    speciesRepository,
    iNatService,
  );
  final jobRepository = EnrichmentJobRepository();
  const ownershipRepository = EnrichmentOwnershipRepository();
  const projectionRepository = DeckEnrichmentProjectionRepository();
  const claimRepository = EnrichmentWorkClaimRepository();
  const outcomeRepository = EnrichmentWorkOutcomeRepository();
  const maintenanceRepository = EnrichmentWorkMaintenanceRepository();

  // The three queue consumers. Built here rather than by the queue service,
  // which would otherwise have to accept every collaborator they need just to
  // pass it on.
  final coverRunner = CoverJobRunner(
    jobRepository,
    _DeckCoverStoreAdapter(deckService),
    imageService,
  );
  final baseWorker = BaseWorker(
    baseImageEnrichmentService,
    claimRepository,
    outcomeRepository,
    speciesRepository,
  );
  final iNatWorker = INatWorker(
    photoEnrichmentService,
    commonNameEnrichmentService,
    taxonomyEnrichmentService,
    claimRepository,
    outcomeRepository,
    ownershipRepository,
    iNatCacheRepository,
    nameResolutionPort: nameResolutionService,
    deckSpeciesMutationPort: _DeckSpeciesMutationAdapter(deckService),
    unresolvedNamesObserver: const _WiringLoggingUnresolvedNamesObserver(),
  );

  final iNatEnrichmentQueueService = INatEnrichmentQueueService(
    coverRunner: coverRunner,
    baseWorker: baseWorker,
    iNatWorker: iNatWorker,
    deckSpeciesSnapshotPort: _DeckSpeciesSnapshotAdapter(deckService),
    allDeckIdsPort: _AllDeckIdsAdapter(deckService),
    jobRepository: jobRepository,
    ownershipRepository: ownershipRepository,
    projectionRepository: projectionRepository,
    maintenanceRepository: maintenanceRepository,
    hostCooldownTracker: hostCooldownTracker,
    backgroundScheduler: backgroundScheduler,
    foregroundServiceKeeper: foregroundServiceKeeper,
    networkAvailability: networkAvailability,
    autoInitialize: false,
    processJobs: processEnrichmentJobs,
  );

  return (
    speciesMediaService: speciesMediaService,
    nameResolutionService: nameResolutionService,
    iNatEnrichmentQueueService: iNatEnrichmentQueueService,
    healthSnapshotService: EnrichmentHealthSnapshotService(
      projectionRepository: projectionRepository,
      maintenanceRepository: maintenanceRepository,
      jobRepository: jobRepository,
    ),
  );
}

class _DeckSpeciesSnapshotAdapter implements DeckSpeciesSnapshotPort {
  final DecksService _deckService;

  const _DeckSpeciesSnapshotAdapter(this._deckService);

  @override
  Future<Set<String>> loadSpeciesIdsForDecks(Set<String> deckIds) {
    return _deckService.getSpeciesIdsByDeckIds(deckIds);
  }
}

class _DeckCoverStoreAdapter implements DeckCoverStorePort {
  final DecksService _deckService;

  const _DeckCoverStoreAdapter(this._deckService);

  @override
  Future<void> updateDeckCoverPath(String deckId, String localPath) {
    return _deckService.updateDeckCoverPath(deckId, localPath);
  }
}

class _DeckSpeciesMutationAdapter implements DeckSpeciesMutationPort {
  final DecksService _deckService;

  const _DeckSpeciesMutationAdapter(this._deckService);

  @override
  Future<void> addSpeciesToDeck(String deckId, Set<String> speciesIds) {
    return _deckService.addSpeciesToDeck(deckId, speciesIds);
  }
}

class _AllDeckIdsAdapter implements AllDeckIdsPort {
  final DecksService _deckService;

  const _AllDeckIdsAdapter(this._deckService);

  @override
  Future<Set<String>> loadAllDeckIds() async {
    final decks = await _deckService.getAllDecks();
    return decks.map((deck) => deck.id).whereType<String>().toSet();
  }
}

class _WiringLoggingUnresolvedNamesObserver
    implements UnresolvedNamesObserverPort {
  const _WiringLoggingUnresolvedNamesObserver();

  @override
  void onNamesUnresolved(String deckId, List<String> unresolvedNames) {
    Logger.debug(
      'bootstrap',
      'Persisted ${unresolvedNames.length} unresolved names for deck=$deckId',
    );
  }
}
