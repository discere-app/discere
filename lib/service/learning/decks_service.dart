import 'dart:core';


import 'package:flutter/material.dart';

import '../../model/learning/base_deck.dart';
import '../../model/learning/deck_stat.dart';
import '../../model/learning/flash_card_stat.dart';
import '../../model/ui/create_deck.dart';
import '../../model/ui/view_deck.dart';
import '../../persistence/deck_repository.dart';
import '../../persistence/flash_card_stat_repository.dart';
import '../../persistence/species_repository.dart';

class DecksService extends ChangeNotifier {
  final DeckRepository _deckRepository;
  final SpeciesRepository _speciesRepository;
  final FlashCardStatRepository _flashCardStatRepository;

  DecksService(this._deckRepository, this._flashCardStatRepository,
      this._speciesRepository);

  Future<void> createDeck(CreateDeck deck) async {
    await _deckRepository.insertDeck(deck);
    await _initializeDeck(deck);
    notifyListeners();
  }

  Future<void> createDeckBySpeciesScientificNames(
    String deckName,
    String deckDescription,
    List<String> scientificNames,
  ) async {
    if (scientificNames.isEmpty) {
      // Leere Liste, nichts zu tun
      return;
    }

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

    if (names.isEmpty) {
      // Alle Namen ungültig, nichts zu tun
      return;
    }

    Set<String> speciesIds =
        await _speciesRepository.getSpeciesIdsByScientificNames(names);

    if (speciesIds.isEmpty) {
      // Keine Arten gefunden, erstelle Deck mit leerer Artenliste
      var deck = CreateDeck(
          name: deckName, description: deckDescription, speciesIds: {});
      await createDeck(deck);
      return;
    }

    var deck = CreateDeck(
        name: deckName, description: deckDescription, speciesIds: speciesIds);
    await createDeck(deck);
  }

  Future<void> _initializeDeck(CreateDeck deck) async {
    final Set<FlashCardStat> flashCardStats = deck.speciesIds!.map((speciesId) {
      return FlashCardStat(speciesId: speciesId, deckId: deck.id!);
    }).toSet();

    await _flashCardStatRepository.insertOrUpdateFlashCardStats(flashCardStats);
  }

  Future<List<ViewDeck>> getAllDecks() async {
    final List<BaseDeck> decks = await _deckRepository.getAllDecks();
    return await _createViewDecks(decks);
  }

  Future<List<ViewDeck>> getDecks(Set<String> deckIds) async {
    final List<BaseDeck> decks = await _deckRepository.getDecksByIds(deckIds);
    return await _createViewDecks(decks);
  }

  Future<void> deleteDeck(String deckId) {
    return _deckRepository.delete(deckId);
  }

  Future<List<ViewDeck>> _createViewDecks(List<BaseDeck> decks) async {
    final List<ViewDeck> viewDecks = [];
    for (BaseDeck deck in decks) {
      DeckStat deckStat = await _flashCardStatRepository.getDeckStat(deck.id!);

      double progress = deckStat.uninitializedCount == 0
          ? 1
          : deckStat.uninitializedCount / deckStat.totalCount;
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
    final switzerland = CreateDeck(
        name: "Schweiz",
        description: "Fische in der Schweiz",
        speciesIds: _schweiz());
    await createDeck(switzerland);
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

  Set<String> _schweiz() {
    return {
      '5424',
      '3022',
      '231',
      '65592',
      '2676',
      '232',
      '258',
      '4481',
      '4877',
      '49362',
      '25792',
      '270',
      '49199',
      '49208',
      '2420',
      '4474',
      '25867',
      '4662',
      '310',
      '4691',
      '289',
      '65134',
      '4605',
      '60240',
      '291',
      '28201',
      '25854',
      '28065',
      '26082',
      '4790',
      '4661',
      '49328',
      '238',
      '62956',
      '49369',
      '6462',
      '269',
      '6377',
      '6378',
      '49197',
      '49192',
      '1450',
      '4782',
      '360',
      '4730',
      '5473',
      '4472',
      '6376',
      '49194',
      '49200',
      '49201',
      '2439',
      '239',
      '4483',
      '65590',
      '246',
      '65320',
      '4875',
      '35',
      '4878',
      '49212',
      '4478',
      '3385',
      '2530',
      '8418',
      '272',
      '2951',
      '268',
      '62353',
      '4471',
      '49193',
      '49206',
      '49195',
      '49203',
      '49207',
      '49204',
      '14249',
      '247',
      '248',
      '4482',
      '6316',
      '271',
      '49105',
      '233',
      '4664',
      '3372',
      '4783',
      '358',
      '48259'
    };
  }
}
