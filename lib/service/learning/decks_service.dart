import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../model/learning/base_deck.dart';
import '../../model/learning/deck_stat.dart';
import '../../model/learning/flash_card_stat.dart';
import '../../model/ui/create_deck.dart';
import '../../model/ui/view_deck.dart';
import '../../persistence/deck_repository.dart';
import '../../persistence/flash_card_stat_repository.dart';
import '../../persistence/species_repository.dart';
import '../common/image_service.dart';
import '../../model/biology/species.dart';

class DecksService extends ChangeNotifier {
  final DeckRepository _deckRepository;
  final SpeciesRepository _speciesRepository;
  final FlashCardStatRepository _flashCardStatRepository;
  final ImageService _imageService;

  DecksService(this._deckRepository, this._flashCardStatRepository,
      this._speciesRepository, this._imageService);

  Future<void> createDeck(CreateDeck deck) async {
    final id = await _deckRepository.insertDeck(deck);
    // Ensure the deck object has the ID for initialization
    final updatedDeck = CreateDeck(
      id: id,
      name: deck.name,
      description: deck.description,
      speciesIds: deck.speciesIds,
    )..coverImagePath = deck.coverImagePath;

    await _initializeDeck(updatedDeck);
    notifyListeners();
  }

  Future<void> updateDeck(
      BaseDeck updatedDeck, Set<String> newSpeciesIds) async {
    // 1. Upsert deck metadata (insertDeck uses conflictAlgorithm: replace)
    await _deckRepository.insertDeck(updatedDeck);

    // 2. Diff species list
    final currentIds =
        await _flashCardStatRepository.getSpeciesIdsByDeckId(updatedDeck.id!);
    final removed = currentIds.difference(newSpeciesIds);
    final added = newSpeciesIds.difference(currentIds);

    // 3. Remove flash-card stats for removed species
    if (removed.isNotEmpty) {
      await _flashCardStatRepository.deleteFlashCardStats(
          updatedDeck.id!, removed);
    }

    // 4. Insert flash-card stats for newly added species (preserves progress for existing)
    if (added.isNotEmpty) {
      final newStats = added.map((speciesId) => FlashCardStat(
        speciesId: speciesId,
        deckId: updatedDeck.id!,
      )).toSet();
      await _flashCardStatRepository.insertOrUpdateFlashCardStats(newStats);
    }

    notifyListeners();
  }

  Future<void> createDeckBySpeciesScientificNames(
    String deckName,
    String deckDescription,
    List<String> scientificNames, {
    String? coverImagePath,
  }) async {
    List<(String, String)> names = scientificNames
        .map((name) {
          List<String> parts = name.split(' ');
          if (parts.length != 2) {
            // Ungültiger Name, überspringen
            return ('', '');
          }
          return (parts[0], parts[1]);
        })
        .where((name) => name.$1.isNotEmpty && name.$2.isNotEmpty)
        .toList();

    Set<String> speciesIds = {};
    if (names.isNotEmpty) {
      speciesIds =
          await _speciesRepository.getSpeciesIdsByScientificNames(names);
    }

    if (speciesIds.isEmpty) {
      // Keine Arten gefunden, erstelle Deck mit leerer Artenliste
      var deck = CreateDeck(
          name: deckName, description: deckDescription, speciesIds: {})
        ..coverImagePath = coverImagePath;
      await createDeck(deck);
      return;
    }

    var deck = CreateDeck(
        name: deckName, description: deckDescription, speciesIds: speciesIds)
      ..coverImagePath = coverImagePath;
    await createDeck(deck);
  }

  Future<void> _initializeDeck(CreateDeck deck) async {
    final speciesIds = deck.speciesIds ?? {};
    if (speciesIds.isEmpty) return;

    final Set<FlashCardStat> flashCardStats = speciesIds.map((speciesId) => FlashCardStat(
      speciesId: speciesId,
      deckId: deck.id!,
    )).toSet();

    await _flashCardStatRepository.insertOrUpdateFlashCardStats(flashCardStats);
  }

  Future<List<ViewDeck>> getAllDecks() async {
    final List<BaseDeck> decks = await _deckRepository.getAllDecks();
    return await _createViewDecks(decks);
  }

  Future<List<ViewDeck>> getDecks(Set<String> deckIds) async {
    final List<BaseDeck> decks = await _getRawDecksByIds(deckIds);
    return await _createViewDecks(decks);
  }

  Future<CreateDeck> getCreateDeck(String deckId) async {
    final List<BaseDeck> decks = await _getRawDecksByIds({deckId});
    if (decks.isEmpty) {
      throw Exception('Deck not found: $deckId');
    }
    final deck = decks.first;
    final speciesIds =
        await _flashCardStatRepository.getSpeciesIdsByDeckId(deckId);

    return CreateDeck(
      id: deck.id,
      name: deck.name,
      description: deck.description,
      speciesIds: speciesIds,
    )..coverImagePath = deck.coverImagePath;
  }

  Future<List<Species>> getSpeciesByDeckId(String deckId) async {
    final speciesIds =
        await _flashCardStatRepository.getSpeciesIdsByDeckId(deckId);
    if (speciesIds.isEmpty) return [];

    final speciesSet = await _speciesRepository.getSpecies(speciesIds);
    return speciesSet.toList();
  }

  Future<List<Species>> getSpeciesByIds(Set<String> ids) async {
    if (ids.isEmpty) return [];
    final speciesSet = await _speciesRepository.getSpecies(ids);
    return speciesSet.toList();
  }

  Future<List<BaseDeck>> _getRawDecksByIds(Set<String> deckIds) async {
    return _deckRepository.getDecksByIds(deckIds);
  }

  Future<void> deleteDeck(String deckId) async {
    // 1. Get the deck to find the cover image path
    final decks = await _deckRepository.getDecksByIds({deckId});
    if (decks.isNotEmpty) {
      final coverPath = decks.first.coverImagePath;
      if (coverPath != null && coverPath.isNotEmpty) {
        await _imageService.deleteImage(coverPath);
      }
    }

    // 2. Delete from database
    await _deckRepository.delete(deckId);
    notifyListeners();
  }

  Future<void> createDeckFromQrCode(Barcode barcode) {
    final jsonMap = jsonDecode(barcode.displayValue!) as Map<String, dynamic>;
    final deck = CreateDeck.fromJson(jsonMap);
    return createDeck(deck);
  }

  Future<void> createDeckFromJson(String jsonText) {
    final deck = CreateDeck.fromJsonString(jsonText);
    return createDeck(deck);
  }

  Future<void> importDeckFromText(String text) async {
    if (text.trim().isEmpty) return;
    try {
      // Try JSON first
      final deck = CreateDeck.fromJsonString(text);
      return createDeck(deck);
    } catch (_) {
      // Fallback: treat as list of scientific names (binomials)
      final lines = text
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && l.contains(' '))
          .toList();

      if (lines.isNotEmpty) {
        return createDeckBySpeciesScientificNames(
            "Imported Deck", "Imported from scientific name list", lines);
      }
      rethrow;
    }
  }

  Future<List<ViewDeck>> _createViewDecks(List<BaseDeck> decks) async {
    final List<ViewDeck> viewDecks = [];
    for (BaseDeck deck in decks) {
      DeckStat deckStat = await _flashCardStatRepository.getDeckStat(deck.id!);

      double progress = deckStat.uninitializedCount == 0
          ? 1
          : 1 - (deckStat.uninitializedCount / deckStat.totalCount);
      viewDecks.add(ViewDeck.fromBase(deck, progress));
    }
    return viewDecks;
  }

  Future<void> createDummyDecks() async {
    var allDecks = await getAllDecks();
    if (allDecks.isEmpty) {
      createDeckBySpeciesScientificNames(
          "Haie", "100 bekannteste Haie", _haie());
      await createSwitzerland();
    }
  }

  Future<void> createSwitzerland() async {
    return createDeckBySpeciesScientificNames(
        "Schweiz", "Fische in der Schweiz", _schweiz());
  }

  List<String> _haie() {
    return [
      'Carcharodon carcharias',
      'Galeocerdo cuvier',
      'Prionace glauca',
      'Rhincodon typus',
      'Sphyrna mokarran',
      'Alopias vulpinus',
      'Carcharhinus longimanus',
      'Isurus oxyrinchus',
      'Hexanchus griseus',
      'Cetorhinus maximus',
      'Squalus acanthias',
      'Scyliorhinus canicula',
      'Heterodontus francisci',
      'Carcharhinus limbatus',
      'Mustelus mustelus',
      'Triaenodon obesus',
      'Negaprion brevirostris',
      'Carcharhinus leucas',
      'Lamna nasus',
      'Carcharhinus falciformis',
      'Euprotomicrus bispinatus',
      'Notorynchus cepedianus',
      'Stegostoma fasciatum',
      'Hemiscyllium ocellatum',
      'Mitsukurina owstoni',
      'Carcharhinus amblyrhynchos',
      'Carcharhinus melanopterus',
      'Odontaspis ferox',
      'Heterodontus portusjacksoni',
      'Scyliorhinus stellaris',
      'Ginglymostoma cirratum',
      'Echinorhinus brucus',
      'Carcharhinus plumbeus',
      'Galeorhinus galeus',
      'Cephaloscyllium ventriosum',
      'Apristurus aphyodes',
      'Chlamydoselachus anguineus',
      'Isistius brasiliensis',
      'Squatina squatina',
      'Nebrius ferrugineus',
      'Heptranchias perlo',
      'Eusphyra blochii',
      'Lamnidae ditropis',
      'Oxynotus centrina',
      'Sphyrna lewini',
      'Carcharhinus obscurus',
      'Mustelus henlei',
      'Scymnodon ringens',
      'Somniosus microcephalus',
      'Rhizoprionodon terraenovae',
      'Hemipristis elongata',
      'Carcharhinus perezi',
      'Chiloscyllium punctatum',
      'Paragaleus randalli',
      'Apristurus profundorum',
      'Galeocerdo aduncus',
      'Triaenodon tricuspidatus',
      'Carcharhinus altimus',
      'Atelomycterus marmoratus',
      'Chiloscyllium griseum',
      'Nebrius concolor',
      'Halaelurus natalensis',
      'Asymbolus vincenti',
      'Mustelus antarcticus',
      'Rhizoprionodon porosus',
      'Galeus melastomus',
      'Hemiscyllium hallstromi',
      'Cephaloscyllium isabellum',
      'Apristurus parvipinnis',
      'Mustelus palumbes',
      'Triakis semifasciata',
      'Loxodon macrorhinus',
      'Heterodontus quoyi',
      'Halaelurus buergeri',
      'Carcharhinus dussumieri',
      'Rhynchobatus djiddensis',
      'Carcharhinus sealei',
      'Scyliorhinus hesperius',
      'Centrophorus granulosus',
      'Cephaloscyllium umbratile',
      'Apristurus kampae',
      'Atelomycterus fasciatus',
      'Rhizoprionodon taylori',
      'Galeus polli',
      'Hemiscyllium trispeculare',
      'Chiloscyllium arabicum',
      'Galeocerdo cuvieri',
      'Triakis scyllium',
      'Atelomycterus baliensis',
      'Cephaloscyllium sufflans',
      'Halaelurus alcockii',
      'Mustelus dorsalis',
      'Scyliorhinus torazame',
      'Hemigaleus microstoma',
      'Apristurus sibogae',
      'Cephaloscyllium fasciatum',
      'Rhizoprionodon lalandii',
      'Galeus atlanticus',
      'Halaelurus quagga',
      'Carcharhinus brevipinna'
    ];
  }

  List<String> _schweiz() {
    return [
      'Abramis brama',
      'Alburnoides bipunctatus',
      'Alburnus alburnus',
      'Alburnus arborella',
      'Alburnus chalcoides',
      'Alosa agone',
      'Ameiurus melas',
      'Ameiurus nebulosus',
      'Anguilla anguilla',
      'Barbatula barbatula',
      'Barbus barbus',
      'Barbus caninus',
      'Barbus meridionalis',
      'Barbus plebejus',
      'Blicca bjoerkna',
      'Carassius auratus',
      'Carassius carassius',
      'Carassius gibelio',
      'Chondrostoma nasus',
      'Cobitis bilineata',
      'Cobitis taenia',
      'Coregonus albellus',
      'Coregonus albula',
      'Coregonus alpinus',
      'Coregonus arenicolus',
      'Coregonus candidus',
      'Coregonus confusus',
      'Coregonus duplex',
      'Coregonus fatioi',
      'Coregonus heglingus',
      'Coregonus hiemalis',
      'Coregonus lavaretus',
      'Coregonus macrophthalmus',
      'Coregonus nobilis',
      'Coregonus oxyrinchus',
      'Coregonus palaea',
      'Coregonus pidschian',
      'Coregonus suidteri',
      'Coregonus wartmanni',
      'Coregonus zuerichensis',
      'Coregonus zugensis',
      'Cottus gobio',
      'Cyprinus carpio',
      'Esox lucius',
      'Gasterosteus aculeatus',
      'Gobio gobio',
      'Gymnocephalus cernua',
      'Hucho hucho',
      'Lampetra planeri',
      'Lampetra zanandreai',
      'Lepomis gibbosus',
      'Leucaspius delineatus',
      'Leuciscus aspius',
      'Leuciscus leuciscus',
      'Leucos aula',
      'Lota lota',
      'Micropterus salmoides',
      'Misgurnus fossilis',
      'Oncorhynchus mykiss',
      'Padogobius bonelli',
      'Perca fluviatilis',
      'Petromyzon marinus',
      'Phoxinus phoxinus',
      'Pseudorasbora parva',
      'Pungitius laevis',
      'Rhodeus amarus',
      'Rutilus pigus',
      'Rutilus rutilus',
      'Salariopsis fluviatilis',
      'Salmo cenerinus',
      'Salmo rhodanensis',
      'Salmo trutta',
      'Salvelinus alpinus',
      'Salvelinus fontinalis',
      'Salvelinus namaycush',
      'Salvelinus neocomensis',
      'Salvelinus profundus',
      'Salvelinus umbla',
      'Sander lucioperca',
      'Scardinius erythrophthalmus',
      'Scardinius hesperidicus',
      'Silurus glanis',
      'Squalius cephalus',
      'Squalius squalus',
      'Telestes muticellus',
      'Telestes souffia',
      'Thymallus thymallus',
      'Tinca tinca',
      'Zingel asper',
    ];
  }
}
