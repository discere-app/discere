import 'package:discere/model/biology/species.dart';
import 'package:discere/model/biology/classification.dart';
import 'package:discere/model/learning/base_deck.dart';
import 'package:discere/model/ui/create_deck.dart';
import 'package:discere/service/learning/decks_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';

import 'package:discere/persistence/deck_repository.dart';
import 'package:discere/persistence/species_repository.dart';
import 'package:discere/persistence/flash_card_stat_repository.dart';
import 'package:discere/service/common/image_service.dart';

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
  Future<Set<String>> getSpeciesIdsByScientificNames(
      List<(String, String)> names) async {
    Set<String> ids = {};
    for (var name in names) {
      final species = speciesMap["${name.$1} ${name.$2}"];
      if (species != null) ids.add(species.id);
    }
    return ids;
  }

  @override
  Future<Set<String>> getSpeciesIdsByFullNames(List<String> names) async {
    Set<String> ids = {};
    for (var name in names) {
      final species = speciesMap[name];
      if (species != null) ids.add(species.id);
    }
    return ids;
  }

  @override
  Future<Set<Species>> getSpecies(Set<String> ids) async {
    Set<Species> result = {};
    for (var id in ids) {
      try {
        final spec = speciesMap.values.firstWhere((s) => s.id == id);
        result.add(spec);
      } catch (_) {}
    }
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFlashCardStatRepository implements FlashCardStatRepository {
  List<String> addedSpeciesIds = [];

  @override
  Future<void> insertOrUpdateFlashCardStats(Set<dynamic> stats) async {
    for (var stat in stats) {
      addedSpeciesIds.add(stat.speciesId);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeImageService implements ImageService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late DecksService decksService;
  late FakeDeckRepository fakeDeckRepo;
  late FakeSpeciesRepository fakeSpeciesRepo;
  late FakeFlashCardStatRepository fakeStatRepo;
  late FakeImageService fakeImageService;

  setUp(() {
    fakeDeckRepo = FakeDeckRepository();
    fakeSpeciesRepo = FakeSpeciesRepository();
    fakeStatRepo = FakeFlashCardStatRepository();
    fakeImageService = FakeImageService();

    decksService = DecksService(
      fakeDeckRepo,
      fakeStatRepo,
      fakeSpeciesRepo,
      fakeImageService,
    );
  });

  group('DecksService JSON Import', () {
    test('should import deck from JSON matching CreateDeck format', () async {
      final classification = Classification('', {}, null, '', {}, '', {}, '', {}, null);
      fakeSpeciesRepo.speciesMap['Species 1'] = Species('1', 'Species', '1', 'sp1', {}, classification, []);
      fakeSpeciesRepo.speciesMap['Species 2'] = Species('2', 'Species', '2', 'sp2', {}, classification, []);
      
      final createDeck = CreateDeck(
        name: 'Test JSON Deck',
        description: 'Imported via JSON',
        speciesNames: {'Species 1', 'Species 2'},
        // speciesIds: {'1', '2'}, // Hidden from JSON
      );
      final jsonStr = jsonEncode(createDeck.toJson());

      // Verify speciesIds is NOT in the JSON
      expect(jsonStr, isNot(contains('speciesIds')));

      await decksService.createDeckFromJson(jsonStr);

      expect(fakeDeckRepo.lastCreatedName, 'Test JSON Deck');
      expect(fakeStatRepo.addedSpeciesIds, containsAll(['1', '2']));
    });

    test('should throw error for invalid JSON', () async {
      expect(() => decksService.createDeckFromJson('invalid json'), throwsA(anything));
    });
  });
}
