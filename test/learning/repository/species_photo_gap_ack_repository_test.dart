import 'package:discere/learning/repository/species_photo_gap_ack_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../../support/in_memory_user_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late SpeciesPhotoGapAckRepository repository;

  setUp(() async {
    database = await openInMemoryUserDatabase();
    // species_photo_gap_ack.deck_id has a real FK to decks(id) — the schema
    // now comes from UserDbSchema.create, which enforces it (unlike the
    // hand-picked single-table setup this replaced).
    for (final deckId in const ['deck-1', 'deck-2']) {
      await database.insert('decks', {'id': deckId, 'name': deckId});
    }
    repository = SpeciesPhotoGapAckRepository(database: database);
  });

  tearDown(() async {
    await database.close();
  });

  test('a species with no acknowledgement is not returned', () async {
    final acknowledged = await repository.getAcknowledgedSpeciesIds('deck-1');
    expect(acknowledged, isEmpty);
  });

  test('acknowledge records species ids scoped to the deck', () async {
    await repository.acknowledge('deck-1', {'sp1', 'sp2'});

    final acknowledged = await repository.getAcknowledgedSpeciesIds('deck-1');
    expect(acknowledged, {'sp1', 'sp2'});
  });

  test('acknowledgements for one deck do not leak into another', () async {
    await repository.acknowledge('deck-1', {'sp1'});
    await repository.acknowledge('deck-2', {'sp2'});

    expect(await repository.getAcknowledgedSpeciesIds('deck-1'), {'sp1'});
    expect(await repository.getAcknowledgedSpeciesIds('deck-2'), {'sp2'});
  });

  test('acknowledging the same species twice does not throw', () async {
    await repository.acknowledge('deck-1', {'sp1'});
    await repository.acknowledge('deck-1', {'sp1'});

    expect(await repository.getAcknowledgedSpeciesIds('deck-1'), {'sp1'});
  });

  test('acknowledge with an empty set is a no-op', () async {
    await repository.acknowledge('deck-1', {});
    expect(await repository.getAcknowledgedSpeciesIds('deck-1'), isEmpty);
  });
}
