import 'package:discere/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../model/biology/species_with_local_images.dart';
import '../../model/learning/base_deck.dart';
import '../../service/common/language_service.dart';
import '../../service/common/watchlist_service.dart';
import '../../service/learning/flashcard_service.dart';
import '../../service/learning/spaced_repetition_algorithm.dart';
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
  Map<ReviewGrade, String> _previews = {};

  @override
  void initState() {
    super.initState();
    _flashCardService = Provider.of<FlashCardService>(context, listen: false);
    _watchListService = Provider.of<WatchListService>(context, listen: false);
    _languageService = Provider.of<LanguageService>(context, listen: false);
    _initializeFlashCards();
  }

  void _initializeFlashCards() {
    final future = _flashCardService.getFlashCardsForReview(widget.deck.id!);
    setState(() {
      _flashCardsFuture = future;
      _currentFlashCardIndex = 0;
    });

    future.then((cards) async {
      if (cards.isEmpty) {
        final deckStat = await _flashCardService.getDeckStat(widget.deck.id!);
        if (deckStat.uninitializedCount > 0 && mounted) {
          _showMoreNewFlashCardsAvailable(context);
        }
      }
    });
  }

  SpeciesWithLocalImages getCurrentFlashCard() =>
      _flashCards[_currentFlashCardIndex];

  Future<void> _loadPreviews() async {
    if (_flashCards.isEmpty) return;
    final card = getCurrentFlashCard();
    final previews = await _flashCardService.getPreviewIntervals(
        card.species.id, widget.deck.id!);
    if (mounted) setState(() => _previews = previews);
  }

  Future<void> _onAgain() async {
    await _flashCardService.reviewCard(
        getCurrentFlashCard().species.id, widget.deck.id!, ReviewGrade.again);
    _flashCards.add(getCurrentFlashCard()); // Immediately repeat card
    _showNextFlashCard();
  }

  Future<void> _onHard() async {
    await _flashCardService.reviewCard(
        getCurrentFlashCard().species.id, widget.deck.id!, ReviewGrade.hard);
    _showNextFlashCard();
  }

  Future<void> _onGood() async {
    await _flashCardService.reviewCard(
        getCurrentFlashCard().species.id, widget.deck.id!, ReviewGrade.good);
    _showNextFlashCard();
  }

  Future<void> _onEasy() async {
    await _flashCardService.reviewCard(
        getCurrentFlashCard().species.id, widget.deck.id!, ReviewGrade.easy);
    _showNextFlashCard();
  }

  Future<void> _showNextFlashCard() async {
    if (_currentFlashCardIndex < _flashCards.length - 1) {
      setState(() {
        _currentFlashCardIndex++;
      });
      _loadPreviews();
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
                if (_flashCards.isNotEmpty && _previews.isEmpty) {
                  _loadPreviews();
                }
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
                    if (_flashCards.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      FlashCardButtons(
                        onAgain: _onAgain,
                        onHard: _onHard,
                        onGood: _onGood,
                        onEasy: _onEasy,
                        timeAgain: _previews[ReviewGrade.again] ?? '',
                        timeHard: _previews[ReviewGrade.hard] ?? '',
                        timeGood: _previews[ReviewGrade.good] ?? '',
                        timeEasy: _previews[ReviewGrade.easy] ?? '',
                      ),
                    ],
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
                        .then((_) {
                      if (mounted) _initializeFlashCards();
                    });
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
