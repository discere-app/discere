import 'package:discere/catalog/repository/external_id_cache_repository.dart';
import 'package:discere/catalog/repository/external_id_repository.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/catalog/service/local_species_image_service.dart';
import 'package:discere/diagnostics/service/local_diagnostics.dart';
import 'package:discere/enrichment/repository/enrichment_job_repository.dart';
import 'package:discere/enrichment/repository/enrichment_work_repository.dart';
import 'package:discere/enrichment/repository/inat_photo_cache_repository.dart';
import 'package:discere/enrichment/repository/runtime_common_name_repository.dart';
import 'package:discere/enrichment/service/enrichment_background_scheduler.dart';
import 'package:discere/enrichment/service/enrichment_foreground_service_keeper.dart';
import 'package:discere/enrichment/service/enrichment_job_ports.dart';
import 'package:discere/enrichment/service/enrichment_service.dart';
import 'package:discere/enrichment/service/inat_enrichment_queue_service.dart';
import 'package:discere/enrichment/service/inat_name_resolution_service.dart';
import 'package:discere/enrichment/service/species_media_service.dart';
import 'package:discere/enrichment/service/species_photo_service.dart';
import 'package:discere/enrichment/service/taxonomy_common_name_enrichment_service.dart';
import 'package:discere/external/inaturalist/inaturalist_service.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/shared/service/host_cooldown_tracker.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/service/network_availability.dart';
import 'package:discere/shared/util/logger.dart';

/// Builds the `enrichment` slice's services. Needs [DecksService] (from
/// `learning`) to wire [INatEnrichmentQueueService]'s ports — inverted via
/// the local adapter classes below, since `enrichment` may not import
/// `learning` directly per the module dependency matrix.
({
  EnrichmentService enrichmentService,
  SpeciesMediaService speciesMediaService,
  INatNameResolutionService nameResolutionService,
  INatEnrichmentQueueService iNatEnrichmentQueueService,
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
  required EnrichmentForegroundServiceKeeper foregroundServiceKeeper,
  required NetworkAvailability networkAvailability,
  required HostCooldownTracker hostCooldownTracker,
  required LocalDiagnostics diagnostics,
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
  final runtimeCommonNameRepository = RuntimeCommonNameRepository();
  final enrichmentService = EnrichmentService(
    speciesRepository,
    imageService,
    iNatService,
    iNatCacheRepository,
    externalIdRepository,
    externalIdCacheRepository,
    runtimeCommonNameRepository: runtimeCommonNameRepository,
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
  final iNatEnrichmentQueueService = INatEnrichmentQueueService(
    enrichmentService,
    taxonomyEnrichmentService: taxonomyEnrichmentService,
    deckSpeciesSnapshotPort: _DeckSpeciesSnapshotAdapter(deckService),
    deckCoverStore: _DeckCoverStoreAdapter(deckService),
    imageService: imageService,
    nameResolutionPort: nameResolutionService,
    deckSpeciesMutationPort: _DeckSpeciesMutationAdapter(deckService),
    allDeckIdsPort: _AllDeckIdsAdapter(deckService),
    jobRepository: EnrichmentJobRepository(),
    workRepository: const EnrichmentWorkRepository(),
    hostCooldownTracker: hostCooldownTracker,
    diagnostics: diagnostics,
    backgroundScheduler: backgroundScheduler,
    foregroundServiceKeeper: foregroundServiceKeeper,
    networkAvailability: networkAvailability,
    unresolvedNamesObserver: const _WiringLoggingUnresolvedNamesObserver(),
    autoInitialize: false,
    processJobs: processEnrichmentJobs,
  );

  return (
    enrichmentService: enrichmentService,
    speciesMediaService: speciesMediaService,
    nameResolutionService: nameResolutionService,
    iNatEnrichmentQueueService: iNatEnrichmentQueueService,
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
