import 'dart:io';
import 'dart:math';

import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/catalog/repository/taxonomy_repository.dart';
import 'package:discere/learning/flashcard/answer_options_presenter.dart';
import 'package:discere/learning/flashcard/flashcard_species_presenter.dart';
import 'package:discere/learning/flashcard/service/multiple_choice_distractor_pool_service.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../integration_test/multiple_choice_deck_species.dart';
import '../../../catalog/repository/runtime_common_names_test_schema.dart';

/// Guards the deck `integration_test/learning_modes_test.dart` reviews in
/// multiple-choice mode against the checked-in reference fixture.
///
/// A card whose distractor pool comes up short falls back to flip mode on its
/// own (`DeckPageState._updateCurrentOptions`), so a deck with one badly
/// covered species does not fail loudly — the multiple-choice widget simply
/// never renders, and only for the runs where that species happens to be
/// drawn first. On CI that reads as an integration test failing roughly one
/// run in four for no visible reason. Asserting the property here, on the
/// host and in milliseconds, keeps that off the emulator entirely.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database referenceDb;
  late Database userDb;
  late String referenceDbPath;
  late String userDbPath;

  setUp(() async {
    final suffix =
        '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
    referenceDbPath = join(
      Directory.systemTemp.path,
      'mc_viability_reference_$suffix.db',
    );
    userDbPath = join(Directory.systemTemp.path, 'mc_viability_user_$suffix.db');

    await File(referenceDbPath).writeAsBytes(
      await File('test/fixtures/discere_reference_test.db').readAsBytes(),
      flush: true,
    );
    referenceDb = await openDatabase(referenceDbPath, readOnly: false);
    userDb = await openDatabase(userDbPath);
    await createRuntimeCommonNamesTable(userDb);
  });

  tearDown(() async {
    await referenceDb.close();
    await userDb.close();
    for (final path in [referenceDbPath, userDbPath]) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  });

  test('every species of the multiple-choice deck yields answer options', () async {
    final speciesRepository = SpeciesRepository(
      database: referenceDb,
      userDatabase: userDb,
    );
    final poolService = MultipleChoiceDistractorPoolService(
      taxonomyRepository: TaxonomyRepository(
        database: referenceDb,
        userDatabase: userDb,
      ),
    );
    const optionsPresenter = AnswerOptionsPresenter();
    const speciesPresenter = FlashcardSpeciesPresenter();

    final idsByName = await speciesRepository.resolveFullNames(
      multipleChoiceDeckSpecies,
    );
    expect(
      idsByName.keys,
      containsAll(multipleChoiceDeckSpecies),
      reason:
          'the fixture must contain every species of the deck — add missing '
          'ones to etl/scripts/test_fixture_species.txt and rebuild it',
    );

    final deckSpecies = <Species>[];
    for (final name in multipleChoiceDeckSpecies) {
      final species = await speciesRepository.getSpeciesById(idsByName[name]!);
      expect(species, isNotNull, reason: 'no species row for $name');
      deckSpecies.add(species!);
    }

    for (final current in deckSpecies) {
      final label = speciesPresenter
          .present(
            current,
            Language.en,
            learningMode: LearningMode.species,
            nameType: NameType.commonName,
          )
          .identity
          .primaryName;

      final pool = await poolService.buildPool(
        currentSpecies: current,
        deckSpecies: deckSpecies,
        learningMode: LearningMode.species,
        language: Language.en,
        nameType: NameType.commonName,
      );

      expect(
        optionsPresenter.buildOptions(correctLabel: label, namePool: pool),
        isNotNull,
        reason:
            '"$label" only found ${pool.length} distractor(s) ($pool) and would '
            'fall back to flip mode, so the multiple-choice test would time '
            'out whenever this card is drawn first',
      );
    }
  });
}
