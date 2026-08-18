import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/repository/deck_config_repository.dart';
import 'package:discere/learning/repository/deck_repository.dart';
import 'package:discere/learning/repository/flashcard_stat_repository.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../../mocks.mocks.dart';
import '../../support/in_memory_user_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late FlashcardStatRepository flashcardStatRepository;
  late DecksService decksService;

  setUp(() async {
    database = await openInMemoryUserDatabase();
    flashcardStatRepository = FlashcardStatRepository(database: database);
    decksService = DecksService(
      DeckRepository(database: database),
      flashcardStatRepository,
      MockSpeciesRepository(),
      MockImageService(),
      deckConfigRepository: DeckConfigRepository(database: database),
    );
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'getTotalDistinctSpeciesCount returns 0 for an empty database',
    () async {
      expect(await flashcardStatRepository.getTotalDistinctSpeciesCount(), 0);
    },
  );

  test('getTotalDistinctSpeciesCount counts each species once across decks, '
      'even when shared between them', () async {
    await decksService.createDeck(
      CreateDeck(name: 'Deck A', description: '', speciesIds: {'sp1', 'sp2'}),
    );
    await decksService.createDeck(
      CreateDeck(
        name: 'Deck B',
        // sp2 is shared with Deck A — must not be double-counted.
        description: '',
        speciesIds: {'sp2', 'sp3'},
      ),
    );

    expect(await flashcardStatRepository.getTotalDistinctSpeciesCount(), 3);
  });
}
