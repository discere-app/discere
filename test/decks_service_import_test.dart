import 'package:discere/model/biology/species.dart';
import 'package:discere/model/biology/classification.dart';
import 'package:discere/model/language.dart';
import 'package:discere/model/learning/base_deck.dart';
import 'package:discere/model/ui/create_deck.dart';
import 'package:discere/service/learning/decks_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';

import 'package:discere/persistence/deck_repository.dart';
import 'package:discere/persistence/species_repository.dart';
import 'package:discere/persistence/flash_card_stat_repository.dart';

// Manual Mocks
class FakeDeckRepository implements DeckRepository {
  String? lastCreatedName;
  String? lastCreatedDescription;
  
  @override
  Future<String> insertDeck(covariant BaseDeck deck) async {
    lastCreatedName = deck.name;
    lastCreatedDescription = deck.description;
    return 'new-deck-id';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSpeciesRepository implements SpeciesRepository {
  Map<String, Species> speciesMap = {};

  @override
  Future<Species?> getSpeciesByBinomialName(String binomialName) async {
    return speciesMap[binomialName];
  }

  @override
  Future<Set<String>> getSpeciesIdsByScientificNames(List<(String, String)> names) async {
    Set<String> ids = {};
    for (var name in names) {
      final species = speciesMap["${name.$1} ${name.$2}"];
      if (species != null) ids.add(species.id);
    }
    return ids;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFlashCardStatRepository implements FlashCardStatRepository {
  List<String> addedSpeciesIds = [];

  @override
  Future<void> upsertFlashCardStat(String deckId, String speciesId) async {
    addedSpeciesIds.add(speciesId);
  }

  @override
  Future<void> insertOrUpdateFlashCardStats(Set<dynamic> stats) async {
     for (var stat in stats) {
       addedSpeciesIds.add(stat.speciesId);
     }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late DecksService decksService;
  late FakeDeckRepository fakeDeckRepo;
  late FakeSpeciesRepository fakeSpeciesRepo;
  late FakeFlashCardStatRepository fakeStatRepo;

  setUp(() {
    fakeDeckRepo = FakeDeckRepository();
    fakeSpeciesRepo = FakeSpeciesRepository();
    fakeStatRepo = FakeFlashCardStatRepository();

    decksService = DecksService(
      fakeDeckRepo,
      fakeStatRepo,
      fakeSpeciesRepo,
    );
  });

  group('DecksService.importDeckFromText', () {
    test('should import deck from JSON matching CreateDeck format', () async {
      final createDeck = CreateDeck(
        name: 'Test JSON Deck',
        description: 'Imported via JSON',
        speciesIds: {'1', '2'},
      );
      final jsonStr = jsonEncode(createDeck.toJson());

      await decksService.importDeckFromText(jsonStr);

      expect(fakeDeckRepo.lastCreatedName, 'Test JSON Deck');
      expect(fakeStatRepo.addedSpeciesIds, containsAll(['1', '2']));
    });

    test('should import deck from raw list of binomial names', () async {
      final rawText = 'Carcharodon carcharias\nGaleocerdo cuvier\nUnknown Species';

      // Setup fake species definitions
      final classification1 = Classification('Carcharodon', {}, null, 'Lamnidae', {}, 'Lamniformes', {}, 'Chondrichthyes', {}, null);
      final classification2 = Classification('Galeocerdo', {}, null, 'Carcharhinidae', {}, 'Carcharhiniformes', {}, 'Chondrichthyes', {}, null);

      fakeSpeciesRepo.speciesMap['Carcharodon carcharias'] = 
          Species('1', 'carcharias', {Language.en: 'Great White'}, classification1, []);
      fakeSpeciesRepo.speciesMap['Galeocerdo cuvier'] = 
          Species('2', 'cuvier', {Language.en: 'Tiger Shark'}, classification2, []);

      await decksService.importDeckFromText(rawText);

      expect(fakeDeckRepo.lastCreatedName, 'Imported Deck');
      expect(fakeStatRepo.addedSpeciesIds, containsAll(['1', '2']));
      expect(fakeStatRepo.addedSpeciesIds.length, 2); // 'Unknown Species' skipped
    });

    test('should not call creation for empty text', () async {
      await decksService.importDeckFromText('');
      expect(fakeDeckRepo.lastCreatedName, isNull);
    });
  });
}
