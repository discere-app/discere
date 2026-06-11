import 'dart:async';

import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/service/user_preferences_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../../theme/app_spacing.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/enrichment/service/inat_enrichment_queue_service.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/flashcard_stat.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:discere/learning/service/fsrs_service.dart';
import 'package:discere/learning/flashcard/flashcard_buttons.dart';
import 'package:discere/learning/flashcard/flashcard_widget.dart';

class DeckPage extends StatefulWidget {
  final BaseDeck deck;

  const DeckPage({required this.deck, super.key});

  @override
  DeckPageState createState() => DeckPageState();
}

class DeckPageState extends State<DeckPage> {
  late final FlashcardService _flashcardService;
  late final INatEnrichmentQueueService _enrichmentQueueService;
  late Future<List<SpeciesWithLocalImages>> _flashCardsFuture;
  late DeckEnrichmentInfo _lastEnrichmentInfo;
  late List<SpeciesWithLocalImages> _flashCards;
  int _currentFlashcardIndex = 0;
  Map<ReviewGrade, String> _previews = {};
  final Set<String> _singleImageAttemptedSpeciesIds = <String>{};
  bool _isPrioritizedImageLoadInFlight = false;
  final GlobalKey _againKey = GlobalKey();
  final GlobalKey _hardKey = GlobalKey();
  final GlobalKey _goodKey = GlobalKey();
  final GlobalKey _easyKey = GlobalKey();
  final GlobalKey _watchlistButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _flashcardService = Provider.of<FlashcardService>(context, listen: false);
    _enrichmentQueueService = Provider.of<INatEnrichmentQueueService>(
      context,
      listen: false,
    );
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
        _maybeShowFlashcardTutorial();
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

  Future<void> _onGrade(ReviewGrade grade) async {
    final stat = await _flashcardService.reviewCard(
      getCurrentFlashcard().species.id,
      widget.deck.id!,
      grade,
      notificationTitle: context.loc.notificationDailyTitle,
      notificationBodyBuilder: (count) =>
          context.loc.notificationDailyBody(count),
    );

    // Cards still in learning/relearning get re-added to the queue
    if (stat.cardState == CardState.learning ||
        stat.cardState == CardState.relearning) {
      _flashCards.add(getCurrentFlashcard());
    }

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
      appBar: AppBar(title: Text(widget.deck.name)),
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
                              watchlistKey: _watchlistButtonKey,
                            ),
                    ),
                    if (_flashCards.isNotEmpty) ...[
                      AppSpacing.heightS24,
                      FlashcardButtons(
                        onAgain: () => _onGrade(ReviewGrade.again),
                        onHard: () => _onGrade(ReviewGrade.hard),
                        onGood: () => _onGrade(ReviewGrade.good),
                        onEasy: () => _onGrade(ReviewGrade.easy),
                        timeAgain: _previews[ReviewGrade.again] ?? '',
                        timeHard: _previews[ReviewGrade.hard] ?? '',
                        timeGood: _previews[ReviewGrade.good] ?? '',
                        timeEasy: _previews[ReviewGrade.easy] ?? '',
                        againKey: _againKey,
                        hardKey: _hardKey,
                        goodKey: _goodKey,
                        easyKey: _easyKey,
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

  void _maybeShowFlashcardTutorial() {
    final prefs = Provider.of<UserPreferencesService>(context, listen: false);
    if (prefs.hasSeenFlashcardTutorial) return;
    prefs.hasSeenFlashcardTutorial = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) _showFlashcardTutorial();
    });
  }

  void _showFlashcardTutorial() {
    final loc = context.loc;
    TutorialCoachMark(
      targets: [
        TargetFocus(
          identify: 'again',
          keyTarget: _againKey,
          shape: ShapeLightFocus.RRect,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              child: _buildCoachMarkContent(
                loc.flashcardButtonAgain,
                loc.tutorialFlashcardAgainDescription,
              ),
            ),
          ],
        ),
        TargetFocus(
          identify: 'hard',
          keyTarget: _hardKey,
          shape: ShapeLightFocus.RRect,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              child: _buildCoachMarkContent(
                loc.flashcardButtonHard,
                loc.tutorialFlashcardHardDescription,
              ),
            ),
          ],
        ),
        TargetFocus(
          identify: 'good',
          keyTarget: _goodKey,
          shape: ShapeLightFocus.RRect,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              child: _buildCoachMarkContent(
                loc.flashcardButtonGood,
                loc.tutorialFlashcardGoodDescription,
              ),
            ),
          ],
        ),
        TargetFocus(
          identify: 'easy',
          keyTarget: _easyKey,
          shape: ShapeLightFocus.RRect,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              child: _buildCoachMarkContent(
                loc.flashcardButtonEasy,
                loc.tutorialFlashcardEasyDescription,
              ),
            ),
          ],
        ),
        TargetFocus(
          identify: 'watchlist',
          keyTarget: _watchlistButtonKey,
          shape: ShapeLightFocus.Circle,
          paddingFocus: 8,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              child: _buildCoachMarkContent(
                loc.tutorialFlashcardWatchlistTitle,
                loc.tutorialFlashcardWatchlistDescription,
              ),
            ),
          ],
        ),
      ],
      colorShadow: Colors.black,
      opacityShadow: 0.85,
      paddingFocus: 8,
      textSkip: loc.tutorialSkip,
      onSkip: () => true,
    ).show(context: context);
  }

  Widget _buildCoachMarkContent(String title, String body) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(color: Colors.white, fontSize: 14)),
        ],
      ),
    );
  }

}
