import 'dart:io';

import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/repository/deprecated_species_name_repository.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/learning/decks/service/deck_update_applier.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/shared/persistence/user_data_writes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../mocks.mocks.dart';

/// The deck update against a reference database that keeps species no
/// source delivers any more: a remote deck that still lists one must not
/// read as dropping it, nor bring one into a deck that lacks it.
///
/// Runs against a copy of the fixture with Prionace glauca turned into a
/// deprecated species — gone from `species_name_lookup`, as the build
/// leaves it — and a deprecated twin of Amphiprion ocellaris under its own
/// ID.
const _blueShark = 'discere:species:834';
const _clownfish = 'discere:species:6002';
const _deprecatedClownfish = 'discere:species:999001';

Species _species(String id) => Species(
  id,
  id,
  'fishbase',
  id,
  const {},
  Classification(
    '',
    const {},
    null,
    '',
    const {},
    '',
    const {},
    '',
    const {},
    null,
  ),
  const [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory tempDir;
  late Database referenceDb;
  late MockDecksService decksService;
  late DeckUpdateApplier applier;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('deck_update_deprecated');
    final path = p.join(tempDir.path, 'reference.db');
    await File('test/fixtures/discere_reference_test.db').copy(path);
    referenceDb = await databaseFactoryFfi.openDatabase(path);
    await referenceDb.execute(
      "UPDATE species SET status = 'deprecated' WHERE id = ?",
      [_blueShark],
    );
    await referenceDb.execute(
      'DELETE FROM species_name_lookup WHERE species_id = ?',
      [_blueShark],
    );
    await referenceDb.execute(
      'INSERT INTO species (id, external_id, external_source, name, genus, '
      "status) SELECT ?, '999001', external_source, name, genus, "
      "'deprecated' FROM species WHERE id = ?",
      [_deprecatedClownfish, _clownfish],
    );
    await referenceDb.execute(
      'INSERT INTO species_scientific_names (species_id, name, '
      'normalized_name, name_status, source, is_preferred) '
      "VALUES (?, 'Amphiprion ocellaris', 'amphiprion ocellaris', 'valid', "
      "'fishbase', 1)",
      [_deprecatedClownfish],
    );

    decksService = MockDecksService();
    when(decksService.getSpeciesByIds(any)).thenAnswer(
      (invocation) async => [
        for (final id in invocation.positionalArguments.single as Set<String>)
          _species(id),
      ],
    );
    applier = DeckUpdateApplier(
      decksService,
      SpeciesRepository(database: referenceDb),
      deprecatedNames: DeprecatedSpeciesNameRepository(database: referenceDb),
      userDataWrites: UserDataWrites(),
    );
  });

  tearDown(() async {
    await referenceDb.close();
    await tempDir.delete(recursive: true);
  });

  void deckHolds(Set<String> speciesIds) {
    when(decksService.getSpeciesByDeckId('deck')).thenAnswer(
      (_) async => [for (final id in speciesIds) _species(id)],
    );
  }

  CreateDeck remoteListing(Set<String> names) =>
      CreateDeck(name: 'Remote', description: '', speciesNames: names);

  test('a deprecated species the deck holds and the remote deck lists is '
      'neither removed nor added', () async {
    deckHolds({_blueShark, _clownfish});

    final diff = await applier.diff(
      'deck',
      remoteListing({'Prionace glauca', 'Amphiprion ocellaris'}),
    );

    expect(diff.removedSpecies, isEmpty);
    expect(diff.addedSpecies, isEmpty);
    expect(diff.unresolvedAddedNames, isEmpty);
  });

  test('a deprecated species the deck does not hold is not added', () async {
    deckHolds({_clownfish});

    final diff = await applier.diff(
      'deck',
      remoteListing({'Prionace glauca', 'Amphiprion ocellaris'}),
    );

    expect(diff.addedSpecies, isEmpty);
    expect(diff.removedSpecies, isEmpty);
    expect(diff.unresolvedAddedNames, ['Prionace glauca']);
  });

  test('a name that matches an active and a deprecated species resolves to '
      'the active one', () async {
    deckHolds({_deprecatedClownfish});

    final diff = await applier.diff(
      'deck',
      remoteListing({'Amphiprion ocellaris'}),
    );

    expect(diff.addedSpecies.map((s) => s.id), [_clownfish]);
    expect(diff.removedSpecies.map((s) => s.id), [_deprecatedClownfish]);
  });
}
