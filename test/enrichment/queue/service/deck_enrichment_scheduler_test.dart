import 'package:discere/enrichment/pipeline/repository/enrichment_ownership_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_claim_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_outcome_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_tables.dart';
import 'package:discere/enrichment/pipeline/service/inat_worker.dart';
import 'package:discere/enrichment/ports/enrichment_job_ports.dart';
import 'package:discere/enrichment/queue/repository/enrichment_job_repository.dart';
import 'package:discere/enrichment/queue/service/deck_enrichment_scheduler.dart';
import 'package:discere/enrichment/queue/service/enrichment_background_scheduler.dart';
import 'package:discere/enrichment/service/deck_membership_lock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../../../mocks.mocks.dart';
import '../../../support/in_memory_user_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late EnrichmentJobRepository jobRepository;
  late EnrichmentOwnershipRepository ownershipRepository;
  late _InMemoryDecks decks;
  late _RecordingBackgroundScheduler backgroundScheduler;
  late DeckMembershipLock deckMembershipLock;
  late DeckEnrichmentScheduler scheduler;
  late INatWorker worker;

  setUp(() async {
    database = await openInMemoryUserDatabase();
    jobRepository = EnrichmentJobRepository(database);
    ownershipRepository = EnrichmentOwnershipRepository(database);
    decks = _InMemoryDecks();
    backgroundScheduler = _RecordingBackgroundScheduler();
    deckMembershipLock = DeckMembershipLock();
    scheduler = DeckEnrichmentScheduler(
      jobRepository: jobRepository,
      ownershipRepository: ownershipRepository,
      deckSpeciesSnapshotPort: decks,
      backgroundScheduler: backgroundScheduler,
      deckMembershipLock: deckMembershipLock,
    );
    worker = INatWorker(
      MockINatPhotoEnrichmentService(),
      MockSpeciesCommonNameEnrichmentService(),
      MockTaxonomyCommonNameEnrichmentService(),
      EnrichmentWorkClaimRepository(database),
      EnrichmentWorkOutcomeRepository(database),
      ownershipRepository,
      MockINatPhotoCacheRepository(),
      deckMembershipLock: deckMembershipLock,
      deckSpeciesMutationPort: decks,
    );
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> schedule(
    List<String> deckIds, {
    bool includeINatPhotos = true,
    bool includeCommonNames = true,
    Map<String, List<String>> unresolvedNamesByDeckId = const {},
  }) {
    return scheduler.schedule(
      deckIds,
      includeINatPhotos: includeINatPhotos,
      includeCommonNames: includeCommonNames,
      coverImageUrlsByDeckId: const {},
      unresolvedNamesByDeckId: unresolvedNamesByDeckId,
    );
  }

  /// `(wants_inat_photos, wants_common_names)` of every species-work row
  /// for [speciesId] — empty when the queue does not track it.
  Future<List<(Object?, Object?)>> consentOf(String speciesId) async {
    final rows = await database.query(
      EnrichmentWorkTables.speciesWork,
      where: 'species_id = ?',
      whereArgs: [speciesId],
    );
    return [
      for (final row in rows)
        (row['wants_inat_photos'], row['wants_common_names']),
    ];
  }

  Future<void> queueNameWithoutConsent() => schedule(
    ['deck-1'],
    includeINatPhotos: false,
    includeCommonNames: false,
    unresolvedNamesByDeckId: const {
      'deck-1': ['Unknown fish'],
    },
  );

  test('a name the worker resolves while its deck is being scheduled keeps '
      'its species and the consent given', () async {
    await queueNameWithoutConsent();
    late Future<void> registration;
    decks.duringNextSnapshot = () {
      registration = worker.registerResolvedName(
        'deck-1',
        'Unknown fish',
        'sp-resolved',
      );
    };

    await schedule(['deck-1']);
    await registration;

    expect(await ownershipRepository.loadAllDeckSpeciesSnapshots(), {
      'deck-1': {'sp-resolved'},
    });
    expect(await consentOf('sp-resolved'), [(1, 1)]);
  });

  test('a name the worker resolved before the consent was given gets the '
      'consent', () async {
    await queueNameWithoutConsent();
    await worker.registerResolvedName('deck-1', 'Unknown fish', 'sp-resolved');
    expect(await consentOf('sp-resolved'), [(0, 0)]);

    await schedule(['deck-1']);

    expect(await consentOf('sp-resolved'), [(1, 1)]);
  });

  test('loads the species of every scheduled deck in one snapshot', () async {
    decks.speciesIdsByDeckId['deck-1'] = {'sp1'};
    decks.speciesIdsByDeckId['deck-2'] = {'sp2'};

    await schedule(['deck-1', 'deck-2']);

    expect(decks.snapshotRequests, [
      {'deck-1', 'deck-2'},
    ]);
    expect(await ownershipRepository.loadAllDeckSpeciesSnapshots(), {
      'deck-1': {'sp1'},
      'deck-2': {'sp2'},
    });
  });

  test('cancel drops the deck\'s job and species and its background '
      'processing', () async {
    decks.speciesIdsByDeckId['deck-1'] = {'sp1'};
    await schedule(['deck-1']);

    await scheduler.cancel('deck-1');

    expect(await jobRepository.loadJob('deck-1'), isNull);
    expect(await ownershipRepository.loadAllDeckSpeciesSnapshots(), isEmpty);
    expect(backgroundScheduler.cancelledDeckIds, ['deck-1']);
  });
}

/// The decks' species as the learning slice holds them, recording which
/// decks each snapshot asked for. [duringNextSnapshot] runs once the next
/// snapshot has been read, before it is answered — something that happens
/// to the decks while the snapshot is in flight.
class _InMemoryDecks
    implements DeckSpeciesSnapshotPort, DeckSpeciesMutationPort {
  final Map<String, Set<String>> speciesIdsByDeckId = {};
  final List<Set<String>> snapshotRequests = [];
  void Function()? duringNextSnapshot;

  @override
  Future<Map<String, Set<String>>> loadSpeciesIdsByDeckId(
    Set<String> deckIds,
  ) async {
    snapshotRequests.add(deckIds);
    final snapshot = {
      for (final deckId in deckIds)
        deckId: {...?speciesIdsByDeckId[deckId]},
    };
    final sideEffect = duringNextSnapshot;
    duringNextSnapshot = null;
    sideEffect?.call();
    return snapshot;
  }

  @override
  Future<void> addSpeciesToDeck(String deckId, Set<String> speciesIds) async {
    speciesIdsByDeckId.putIfAbsent(deckId, () => {}).addAll(speciesIds);
  }
}

class _RecordingBackgroundScheduler implements EnrichmentBackgroundScheduler {
  final List<String> cancelledDeckIds = [];

  @override
  Future<void> cancelProcessingForDeck(String deckId) async {
    cancelledDeckIds.add(deckId);
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> cancelAllPendingProcessing() async {}
}
