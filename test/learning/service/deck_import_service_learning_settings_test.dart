import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/learning/model/review_mode.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/learning_test_stack.dart';

/// The learning settings a deck carries, applied on import and written on
/// sharing, against real databases.
const _deckJson = '''
{
  "name": "Sharks",
  "description": "",
  "speciesNames": ["Carcharodon carcharias", "Prionace glauca"],
  "learningMode": "genus",
  "nameType": "scientificName",
  "reviewMode": "multipleChoice"
}
''';

/// A config's learning mode, name type, review mode and retention.
(LearningMode, NameType, ReviewMode, double) _settingsOf(DeckConfig config) => (
  config.learningMode,
  config.nameType,
  config.reviewMode,
  config.desiredRetention,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LearningTestStack stack;

  Future<(LearningMode, NameType, ReviewMode, double)> settingsOf(
    String deckId,
  ) async {
    await stack.settled();
    return _settingsOf(await stack.deckConfigs.getOrDefault(deckId));
  }

  setUp(() async {
    stack = await LearningTestStack.open();
    stack.preferences.defaultDesiredRetention = 0.85;
  });

  tearDown(() => stack.close());

  test('an imported deck starts with the settings it carries and the '
      'user\'s retention', () async {
    final result = await stack.importService.importDecks([
      CreateDeck.fromJsonString(_deckJson),
    ]);

    expect(await settingsOf(result.importedDeckIds.single), (
      LearningMode.genus,
      NameType.scientificName,
      ReviewMode.multipleChoice,
      0.85,
    ));
  });

  test('an imported deck that carries none starts at the defaults', () async {
    final result = await stack.importService.importDecks([
      CreateDeck(
        name: 'Plain',
        description: '',
        speciesNames: {'Rhincodon typus'},
      ),
    ]);

    expect(await settingsOf(result.importedDeckIds.single), (
      LearningMode.species,
      NameType.commonName,
      ReviewMode.flip,
      0.85,
    ));
  });

  test('a deck created from a reviewed species list starts with the '
      'settings chosen for it', () async {
    final created = await stack.importService.importDeckFromSpeciesNames(
      name: 'Reviewed',
      description: '',
      scientificNames: ['Carcharodon carcharias'],
      learningMode: LearningMode.family,
      nameType: NameType.scientificName,
      reviewMode: ReviewMode.multipleChoice,
    );

    expect(await settingsOf(created.deckId), (
      LearningMode.family,
      NameType.scientificName,
      ReviewMode.multipleChoice,
      0.85,
    ));
  });

  test('a shared deck carries its current settings, and its copy starts '
      'with them', () async {
    final imported = await stack.importService.importDecks([
      CreateDeck.fromJsonString(_deckJson),
    ]);
    final deckId = imported.importedDeckIds.single;
    await stack.settled();
    // Changed after the import: the shared deck carries what the deck has
    // now, not what it came with.
    await stack.deckConfigs.save(
      DeckConfig(
        deckId: deckId,
        learningMode: LearningMode.family,
        nameType: NameType.commonName,
        reviewMode: ReviewMode.flip,
      ),
    );

    final shared = (await stack.decksService.getCreateDeck(deckId)).toJson();
    final copy = await stack.importService.importDecks([
      CreateDeck.fromJson(shared),
    ]);

    expect(
      (shared['learningMode'], shared['nameType'], shared['reviewMode']),
      ('family', 'commonName', 'flip'),
    );
    expect(await settingsOf(copy.importedDeckIds.single), (
      LearningMode.family,
      NameType.commonName,
      ReviewMode.flip,
      0.85,
    ));
  });
}
