// Covers the temporary DeckSourceIdBackfillService (1.0.4 rollout) — delete
// this file alongside that service; see its class doc for the removal plan.

import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/service/deck_source_id_backfill_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockDeckRepository mockDeckRepo;
  late MockRemoteDeckService mockRemoteDeckService;
  late DeckSourceIdBackfillService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockDeckRepo = MockDeckRepository();
    mockRemoteDeckService = MockRemoteDeckService();
    service = DeckSourceIdBackfillService(mockDeckRepo, mockRemoteDeckService);
  });

  test(
    'does nothing and marks done without a network call when no local deck '
    'needs backfilling',
    () async {
      when(mockDeckRepo.getAllDecks()).thenAnswer(
        (_) async => [
          BaseDeck('d1', 'Critter', 'desc', sourceId: 'already-set'),
        ],
      );

      await service.runIfNeeded();

      verifyNever(mockRemoteDeckService.fetchRemoteDecks());
      verifyNever(mockDeckRepo.updateSourceMetadata(any, sourceId: anyNamed('sourceId')));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('deck_source_id_backfill_done'), isTrue);
    },
  );

  test('backfills a deck matched by exact name', () async {
    when(
      mockDeckRepo.getAllDecks(),
    ).thenAnswer((_) async => [BaseDeck('d1', 'Critter', 'desc')]);
    final remoteUpdatedAt = DateTime.utc(2026, 4, 1, 17, 41, 52);
    when(mockRemoteDeckService.fetchRemoteDecks()).thenAnswer(
      (_) async => [
        CreateDeck(
          name: 'Critter',
          description: 'remote desc',
          sourceId: 'catalog-uuid-critter',
          updatedAt: remoteUpdatedAt,
        ),
      ],
    );
    when(
      mockDeckRepo.updateSourceMetadata(
        any,
        sourceId: anyNamed('sourceId'),
        updatedAt: anyNamed('updatedAt'),
      ),
    ).thenAnswer((_) async {});

    await service.runIfNeeded();

    verify(
      mockDeckRepo.updateSourceMetadata(
        'd1',
        sourceId: 'catalog-uuid-critter',
        updatedAt: remoteUpdatedAt,
      ),
    ).called(1);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('deck_source_id_backfill_done'), isTrue);
  });

  test(
    'skips a deck whose name matches more than one catalog entry',
    () async {
      when(
        mockDeckRepo.getAllDecks(),
      ).thenAnswer((_) async => [BaseDeck('d1', 'Mittelmeer', 'desc')]);
      when(mockRemoteDeckService.fetchRemoteDecks()).thenAnswer(
        (_) async => [
          CreateDeck(
            name: 'Mittelmeer',
            description: 'a',
            sourceId: 'uuid-a',
          ),
          CreateDeck(
            name: 'Mittelmeer',
            description: 'b',
            sourceId: 'uuid-b',
          ),
        ],
      );

      await service.runIfNeeded();

      verifyNever(
        mockDeckRepo.updateSourceMetadata(any, sourceId: anyNamed('sourceId')),
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('deck_source_id_backfill_done'), isTrue);
    },
  );

  test('skips a deck with no matching catalog name', () async {
    when(
      mockDeckRepo.getAllDecks(),
    ).thenAnswer((_) async => [BaseDeck('d1', 'Meine eigenen Fische', 'desc')]);
    when(mockRemoteDeckService.fetchRemoteDecks()).thenAnswer(
      (_) async => [
        CreateDeck(name: 'Critter', description: 'x', sourceId: 'uuid-x'),
      ],
    );

    await service.runIfNeeded();

    verifyNever(
      mockDeckRepo.updateSourceMetadata(any, sourceId: anyNamed('sourceId')),
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('deck_source_id_backfill_done'), isTrue);
  });

  test(
    'does not mark done when the catalog fetch fails, so it retries next time',
    () async {
      when(
        mockDeckRepo.getAllDecks(),
      ).thenAnswer((_) async => [BaseDeck('d1', 'Critter', 'desc')]);
      when(
        mockRemoteDeckService.fetchRemoteDecks(),
      ).thenThrow(Exception('network down'));

      await service.runIfNeeded();

      verifyNever(
        mockDeckRepo.updateSourceMetadata(any, sourceId: anyNamed('sourceId')),
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('deck_source_id_backfill_done'), isNot(isTrue));
    },
  );

  test('does not run again once already marked done', () async {
    SharedPreferences.setMockInitialValues({
      'deck_source_id_backfill_done': true,
    });

    await service.runIfNeeded();

    verifyNever(mockDeckRepo.getAllDecks());
    verifyNever(mockRemoteDeckService.fetchRemoteDecks());
  });
}
