import 'package:discere/learning/repository/species_photo_gap_ack_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late SpeciesPhotoGapAckRepository repository;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await openDatabase(inMemoryDatabasePath, version: 1);
    await database.execute(
      await rootBundle.loadString(
        'assets/sql/user_db/tables/create_species_photo_gap_ack.sql',
      ),
    );
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
