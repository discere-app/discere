
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

  void _onThumbUp() {
    _flashCardService.correctButDifficult(
        getCurrentFlashCard().species.id, widget.deck.id!);
    _showNextFlashCard();
  }

  SpeciesWithLocalImages getCurrentFlashCard() =>
      _flashCards[_currentFlashCardIndex];

  void _onThumbDown() {
    _flashCardService.totalBlackout(
        getCurrentFlashCard().species.id, widget.deck.id!);
    _flashCards.add(getCurrentFlashCard()); // Immediately repeat card
    _showNextFlashCard();
  }

  void _showNextFlashCard() {
    setState(() {
      if (_currentFlashCardIndex < _flashCards.length - 1) {
        _currentFlashCardIndex++;
      } else {
        _flashCardService.getDeckStat(widget.deck.id!).then((deckStat) => {
              if (deckStat.uninitializedCount > 0)
                _showMoreNewFlashCardsAvailable(context)
              else
                _showNoMoreFlashCardsAvailableWithNoCards(context)
            });
      }
    });
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
                      onThumbUp: _onThumbUp,
                      onThumbDown: _onThumbDown,
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

  _popupMenuSelected(int value) {
    if (value == _watchList) {
      _watchListService.addSpecies(getCurrentFlashCard().species.id);
    }
  }
}
