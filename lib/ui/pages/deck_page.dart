import 'package:discere/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../model/biology/species_with_local_images.dart';
import '../../model/learning/base_deck.dart';
import '../../service/common/language_service.dart';
import '../../service/common/watchlist_service.dart';
import '../../service/learning/flashcard_service.dart';
import '../components/flashcard_buttons.dart';
import '../components/flashcard_widget.dart';
import 'share_deck_page.dart';

class DeckPage extends StatefulWidget {
  final BaseDeck deck;

  const DeckPage({
    required this.deck,
    super.key,
  });

  @override
  DeckPageState createState() => DeckPageState();
}

class DeckPageState extends State<DeckPage> {
  static const int _watchList = 0;
  static const int _shareDeck = 1;

  late final FlashCardService _flashCardService;
  late final WatchListService _watchListService;
  late final LanguageService _languageService;
  late Future<List<SpeciesWithLocalImages>> _flashCardsFuture;
  late List<SpeciesWithLocalImages> _flashCards;
  int _currentFlashCardIndex = 0;

  @override
  void initState() {
    super.initState();
    _flashCardService = Provider.of<FlashCardService>(context, listen: false);
    _watchListService = Provider.of<WatchListService>(context, listen: false);
    _languageService = Provider.of<LanguageService>(context, listen: false);
    _initializeFlashCards();
  }

  void _initializeFlashCards() {
    setState(() {
      _flashCardsFuture =
          _flashCardService.getFlashCardsForReview(widget.deck.id!);
      _currentFlashCardIndex = 0;
    });
  }

  SpeciesWithLocalImages getCurrentFlashCard() =>
      _flashCards[_currentFlashCardIndex];

  void _onAgain() {
    _flashCardService.totalBlackout(
        getCurrentFlashCard().species.id, widget.deck.id!);
    _flashCards.add(getCurrentFlashCard()); // Immediately repeat card
    _showNextFlashCard();
  }

  void _onHard() {
    _flashCardService.correctButDifficult(
        getCurrentFlashCard().species.id, widget.deck.id!);
    _showNextFlashCard();
  }

  void _onGood() {
    _flashCardService.correctButNeededSomeTime(
        getCurrentFlashCard().species.id, widget.deck.id!);
    _showNextFlashCard();
  }

  void _onEasy() {
    _flashCardService.rateVeryEasy(
        getCurrentFlashCard().species.id, widget.deck.id!);
    _showNextFlashCard();
  }

  Future<void> _showNextFlashCard() async {
    if (_currentFlashCardIndex < _flashCards.length - 1) {
      setState(() {
        _currentFlashCardIndex++;
      });
    } else {
      var deckStat = await _flashCardService.getDeckStat(widget.deck.id!);

      if (!mounted) return;

      if (deckStat.uninitializedCount > 0) {
        _showMoreNewFlashCardsAvailable(context);
      } else {
        _showNoMoreFlashCardsAvailableWithNoCards(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.deck.name),
        actions: [
          PopupMenuButton<int>(
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _watchList,
                child: Text(context.loc.watchListAdd),
              ),
              PopupMenuItem(
                value: _shareDeck,
                child: Text(context.loc.shareDeckTitle),
              )
            ],
            onSelected: (value) => _popupMenuSelected(value),
          )
        ],
      ),
      body: SafeArea(
        child: Center(
          child: FutureBuilder<List<SpeciesWithLocalImages>>(
            future: _flashCardsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const CircularProgressIndicator();
              } else if (snapshot.hasError) {
                return Text('${context.loc.error}: ${snapshot.error}');
              } else {
                _flashCards = snapshot.data ?? [];
                return Column(
                  children: [
                    Expanded(
                      child: _flashCards.isEmpty
                          ? Center(
                              child:
                                  Text(context.loc.commonNoFlashcardsAvailable))
                          : FlashCardWidget(
                              speciesWithLocalImage: getCurrentFlashCard(),
                              languageService: _languageService,
                            ),
                    ),
                    const SizedBox(height: 20),
                    FlashCardButtons(
                      onAgain: _onAgain,
                      onHard: _onHard,
                      onGood: _onGood,
                      onEasy: _onEasy,
                    ),
                  ],
                );
              }
            },
          ),
        ),
      ),
    );
  }

  void _showMoreNewFlashCardsAvailable(BuildContext context) {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(context.loc.flashcardActivateMoreCardsTitle),
              content: Text(context.loc.flashcardActivateMoreCardsDescription),
              actions: [
                TextButton(
                  child: Text(context.loc.commonYes),
                  onPressed: () {
                    _flashCardService
                        .initializeNextBatch(widget.deck.id!)
                        .then((_) => _initializeFlashCards());
                    Navigator.of(context).pop();
                  },
                ),
                TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: Text(context.loc.commonNo))
              ],
            ));
  }

  void _showNoMoreFlashCardsAvailableWithNoCards(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.loc.flashcardNoMoreCardsToLearnTitle),
        content: Text(context.loc.flashcardNoMoreCardsToLearnDescription),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop(); // Zurück zur Startseite
            },
            child: Text(context.loc.commonOk),
          ),
        ],
      ),
    );
  }

  void _popupMenuSelected(int value) {
    if (value == _watchList) {
      _watchListService.addSpecies(getCurrentFlashCard().species.id);
    } else if (value == _shareDeck) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ShareDeckPage(deck: widget.deck),
          fullscreenDialog: true,
        ),
      );
    }
  }
}
