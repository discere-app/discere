import 'dart:async';

import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_spacing.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/enrichment/service/inat_enrichment_queue_service.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:discere/learning/service/spaced_repetition_algorithm.dart';
import 'package:discere/learning/flashcard/flashcard_buttons.dart';
import 'package:discere/learning/flashcard/flashcard_widget.dart';
import 'package:discere/learning/share/share_deck_page.dart';

class DeckPage extends StatefulWidget {
  final BaseDeck deck;

  const DeckPage({required this.deck, super.key});

  @override
  DeckPageState createState() => DeckPageState();
}

class DeckPageState extends State<DeckPage> {
  static const int _watchList = 0;
  static const int _shareDeck = 1;

  late final FlashcardService _flashcardService;
  late final INatEnrichmentQueueService _enrichmentQueueService;
  late final WatchlistService _watchlistService;
  late Future<List<SpeciesWithLocalImages>> _flashCardsFuture;
  late DeckEnrichmentInfo _lastEnrichmentInfo;
  late List<SpeciesWithLocalImages> _flashCards;
  int _currentFlashcardIndex = 0;
  Map<ReviewGrade, String> _previews = {};
  final Set<String> _singleImageAttemptedSpeciesIds = <String>{};
  bool _isPrioritizedImageLoadInFlight = false;

  @override
  void initState() {
    super.initState();
    _flashcardService = Provider.of<FlashcardService>(context, listen: false);
    _enrichmentQueueService = Provider.of<INatEnrichmentQueueService>(
      context,
      listen: false,
    );
    _watchlistService = Provider.of<WatchlistService>(context, listen: false);
    _lastEnrichmentInfo = _enrichmentQueueService.deckInfo(widget.deck.id!);
    _enrichmentQueueService.addListener(_handleEnrichmentQueueChanged);
    unawaited(_enrichmentQueueService.enterInteractivePriorityMode());
    _initializeFlashcards();
  }

  @override
  void dispose() {
    _enrichmentQueueService.removeListener(_handleEnrichmentQueueChanged);
    unawaited(_enrichmentQueueService.leaveInteractivePriorityMode());
    super.dispose();
  }

  void _initializeFlashcards() {
    final future = _flashcardService.getFlashCardsForReview(widget.deck.id!);
    setState(() {
      _flashCardsFuture = future;
      _currentFlashcardIndex = 0;
      _previews = {};
      _singleImageAttemptedSpeciesIds.clear();
    });

    future.then((cards) async {
      if (!mounted) return;
      _flashCards = cards;
      if (cards.isNotEmpty) {
        unawaited(_ensureCurrentFlashcardImage(cards: cards, index: 0));
      }
      if (cards.isEmpty) {
        final deckStat = await _flashcardService.getDeckStat(widget.deck.id!);
        if (deckStat.uninitializedCount > 0 && mounted) {
          if (deckStat.uninitializedCount == deckStat.totalCount) {
            // New deck: auto-initialize first batch
            _flashcardService.initializeNextBatch(widget.deck.id!).then((_) {
              if (mounted) _initializeFlashcards();
            });
          } else {
            _showMoreNewFlashcardsAvailable(context);
          }
        }
      }
    });
  }

  void _handleEnrichmentQueueChanged() {
    final nextInfo = _enrichmentQueueService.deckInfo(widget.deck.id!);
    final hasNewCompletion =
        nextInfo.lastCompletedAt != null &&
        nextInfo.lastCompletedAt != _lastEnrichmentInfo.lastCompletedAt;
    final shouldRefresh =
        !nextInfo.isActive &&
        (hasNewCompletion || _lastEnrichmentInfo.isActive);

    _lastEnrichmentInfo = nextInfo;

    if (!mounted || !shouldRefresh) return;
    _initializeFlashcards();
  }

  SpeciesWithLocalImages getCurrentFlashcard() =>
      _flashCards[_currentFlashcardIndex];

  Future<void> _loadPreviews() async {
    if (_flashCards.isEmpty) return;
    final card = getCurrentFlashcard();
    final previews = await _flashcardService.getPreviewIntervals(
      card.species.id,
      widget.deck.id!,
    );
    if (mounted) setState(() => _previews = previews);
  }

  Future<void> _onAgain() async {
    await _flashcardService.reviewCard(
      getCurrentFlashcard().species.id,
      widget.deck.id!,
      ReviewGrade.again,
      notificationTitle: context.loc.notificationDailyTitle,
      notificationBodyBuilder: (count) =>
          context.loc.notificationDailyBody(count),
    );
    _flashCards.add(getCurrentFlashcard()); // Immediately repeat card
    _showNextFlashcard();
  }

  Future<void> _onHard() async {
    await _flashcardService.reviewCard(
      getCurrentFlashcard().species.id,
      widget.deck.id!,
      ReviewGrade.hard,
      notificationTitle: context.loc.notificationDailyTitle,
      notificationBodyBuilder: (count) =>
          context.loc.notificationDailyBody(count),
    );
    _showNextFlashcard();
  }

  Future<void> _onGood() async {
    await _flashcardService.reviewCard(
      getCurrentFlashcard().species.id,
      widget.deck.id!,
      ReviewGrade.good,
      notificationTitle: context.loc.notificationDailyTitle,
      notificationBodyBuilder: (count) =>
          context.loc.notificationDailyBody(count),
    );
    _showNextFlashcard();
  }

  Future<void> _onEasy() async {
    await _flashcardService.reviewCard(
      getCurrentFlashcard().species.id,
      widget.deck.id!,
      ReviewGrade.easy,
      notificationTitle: context.loc.notificationDailyTitle,
      notificationBodyBuilder: (count) =>
          context.loc.notificationDailyBody(count),
    );
    _showNextFlashcard();
  }

  Future<void> _showNextFlashcard() async {
    if (_currentFlashcardIndex < _flashCards.length - 1) {
      setState(() {
        _currentFlashcardIndex++;
      });
      unawaited(_ensureCurrentFlashcardImage());
      _loadPreviews();
    } else {
      var deckStat = await _flashcardService.getDeckStat(widget.deck.id!);

      if (!mounted) return;

      if (deckStat.uninitializedCount > 0) {
        _showMoreNewFlashcardsAvailable(context);
      } else {
        _showNoMoreFlashcardsAvailableWithNoCards(context);
      }
    }
  }

  Future<void> _ensureCurrentFlashcardImage({
    List<SpeciesWithLocalImages>? cards,
    int? index,
  }) async {
    if (_isPrioritizedImageLoadInFlight) return;
    final targetCards = cards ?? _flashCards;
    if (targetCards.isEmpty) return;

    final targetIndex = index ?? _currentFlashcardIndex;
    if (targetIndex < 0 || targetIndex >= targetCards.length) return;

    final flashcard = targetCards[targetIndex];
    if (flashcard.localPictures.isNotEmpty) return;

    final speciesId = flashcard.species.id;
    if (_singleImageAttemptedSpeciesIds.contains(speciesId)) {
      return;
    }

    _singleImageAttemptedSpeciesIds.add(speciesId);
    _isPrioritizedImageLoadInFlight = true;
    try {
      final updated = await _flashcardService.ensureSingleImageForSpecies(
        speciesId,
      );
      if (!mounted || updated == null) return;

      final latestCards = List<SpeciesWithLocalImages>.from(
        cards ?? _flashCards,
      );
      final latestIndex = latestCards.indexWhere(
        (card) => card.species.id == speciesId,
      );
      if (latestIndex == -1) return;

      latestCards[latestIndex] = updated;
      setState(() {
        _flashCards = latestCards;
        _flashCardsFuture = Future.value(latestCards);
      });
    } finally {
      _isPrioritizedImageLoadInFlight = false;
      if (mounted) {
        unawaited(_ensureCurrentFlashcardImage());
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
                child: Text(
                  context.loc.watchListAdd,
                  key: const Key('deck_popup_watchlist_add'),
                ),
              ),
              PopupMenuItem(
                value: _shareDeck,
                child: Text(
                  context.loc.shareDeckTitle,
                  key: const Key('deck_popup_share_deck'),
                ),
              ),
            ],
            onSelected: (value) => _popupMenuSelected(value),
          ),
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
                          ? Padding(
                              padding: AppSpacing.emptyStatePaddingAll,
                              child: Center(
                                child: Text(
                                  context.loc.commonNoFlashcardsAvailable,
                                  key: const Key(
                                    'no_flashcards_empty_state_text',
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : FlashcardWidget(
                              speciesWithLocalImage: getCurrentFlashcard(),
                              language: widget.deck.language,
                            ),
                    ),
                    if (_flashCards.isNotEmpty) ...[
                      AppSpacing.heightS24,
                      FlashcardButtons(
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

  void _showMoreNewFlashcardsAvailable(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context.loc.flashcardActivateMoreCardsTitle,
          key: const Key('activation_dialog_title'),
        ),
        content: Text(context.loc.flashcardActivateMoreCardsDescription),
        actions: [
          TextButton(
            key: const Key('activation_dialog_yes_button'),
            child: Text(context.loc.commonYes),
            onPressed: () {
              _flashcardService.initializeNextBatch(widget.deck.id!).then((_) {
                if (mounted) _initializeFlashcards();
              });
              Navigator.of(context).pop();
            },
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text(context.loc.commonNo),
          ),
        ],
      ),
    );
  }

  void _showNoMoreFlashcardsAvailableWithNoCards(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context.loc.flashcardNoMoreCardsToLearnTitle,
          key: const Key('no_more_cards_dialog_title'),
        ),
        content: Text(context.loc.flashcardNoMoreCardsToLearnDescription),
        actions: [
          TextButton(
            key: const Key('no_more_cards_ok_button'),
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
      _watchlistService.addSpecies(getCurrentFlashcard().species.id);
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
