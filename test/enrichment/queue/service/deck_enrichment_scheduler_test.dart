import 'package:discere/enrichment/pipeline/repository/enrichment_ownership_repository.dart';
import 'package:discere/enrichment/ports/enrichment_job_ports.dart';
import 'package:discere/enrichment/queue/repository/enrichment_job_repository.dart';
import 'package:discere/enrichment/queue/service/deck_enrichment_scheduler.dart';
import 'package:discere/enrichment/queue/service/enrichment_background_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../../../support/in_memory_user_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late EnrichmentJobRepository jobRepository;
  late EnrichmentOwnershipRepository ownershipRepository;
  late _InMemoryDecks decks;
  late _RecordingBackgroundScheduler backgroundScheduler;
  late DeckEnrichmentScheduler scheduler;

  setUp(() async {
    database = await openInMemoryUserDatabase();
    jobRepository = EnrichmentJobRepository(database);
    ownershipRepository = EnrichmentOwnershipRepository(database);
    decks = _InMemoryDecks();
    backgroundScheduler = _RecordingBackgroundScheduler();
    scheduler = DeckEnrichmentScheduler(
      jobRepository: jobRepository,
      ownershipRepository: ownershipRepository,
      deckSpeciesSnapshotPort: decks,
      backgroundScheduler: backgroundScheduler,
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
/// decks each snapshot asked for.
class _InMemoryDecks implements DeckSpeciesSnapshotPort {
  final Map<String, Set<String>> speciesIdsByDeckId = {};
  final List<Set<String>> snapshotRequests = [];

  @override
  Future<Map<String, Set<String>>> loadSpeciesIdsByDeckId(
    Set<String> deckIds,
  ) async {
    snapshotRequests.add(deckIds);
    return {
      for (final deckId in deckIds)
        deckId: {...?speciesIdsByDeckId[deckId]},
    };
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
