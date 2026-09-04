import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

/// Builds and shows the first-run coach mark over a flashcard review
/// session (DeckPage): flip card / rating buttons or multiple-choice option
/// picker depending on review mode, plus the watchlist button. Pulled out
/// of DeckPageState because the target list is a self-contained template —
/// the page's state only needs to decide *when* to show it (see
/// DeckPageState._maybeShowFlashcardTutorial).
class FlashcardTutorial {
  final LearningMode learningMode;
  final bool isMultipleChoice;
  final bool hasImage;
  final GlobalKey imageKey;
  final GlobalKey optionsKey;
  final GlobalKey againKey;
  final GlobalKey hardKey;
  final GlobalKey goodKey;
  final GlobalKey easyKey;
  final GlobalKey watchlistButtonKey;

  const FlashcardTutorial({
    required this.learningMode,
    required this.isMultipleChoice,
    required this.hasImage,
    required this.imageKey,
    required this.optionsKey,
    required this.againKey,
    required this.hardKey,
    required this.goodKey,
    required this.easyKey,
    required this.watchlistButtonKey,
  });

  void show(BuildContext context) {
    final loc = context.loc;
    TutorialCoachMark(
      targets: _targets(context, loc),
      colorShadow: Colors.black,
      opacityShadow: 0.85,
      paddingFocus: 8,
      textSkip: loc.tutorialSkip,
      // Every step's content sits in the lower half of the card (rating
      // buttons/options, image caption), so the default bottom-right skip
      // button would sit on top of them — move it to the top instead.
      alignSkip: Alignment.topRight,
      onSkip: () => true,
    ).show(context: context);
  }

  /// The intro step notes when the asked-for name is at genus or family
  /// rank rather than species — otherwise nothing in the tour explains why
  /// the back of the card doesn't show a species name.
  String _introDescription(AppLocalizations loc) {
    final base = isMultipleChoice
        ? loc.tutorialFlashcardIntroDescriptionMultipleChoice
        : loc.tutorialFlashcardIntroDescription;
    final rankNote = switch (learningMode) {
      LearningMode.species => null,
      LearningMode.genus => loc.tutorialFlashcardRankNoteGenus,
      LearningMode.family => loc.tutorialFlashcardRankNoteFamily,
    };
    return rankNote == null ? base : '$base $rankNote';
  }

  List<TargetFocus> _targets(BuildContext context, AppLocalizations loc) => [
    // No real widget is highlighted here — a zero-size target centered on
    // screen just gives the overlay text to show without a focus ring, so
    // the tour visibly announces itself as a tour instead of silently
    // pointing at the first button (testers mistook that for an accidental
    // tap/bug).
    TargetFocus(
      identify: 'intro',
      targetPosition: TargetPosition(
        Size.zero,
        Offset(
          MediaQuery.sizeOf(context).width / 2,
          MediaQuery.sizeOf(context).height * 0.4,
        ),
      ),
      paddingFocus: 0,
      enableOverlayTab: true,
      contents: [
        TargetContent(
          align: ContentAlign.bottom,
          child: _content(loc.tutorialIntroTitle, _introDescription(loc)),
        ),
      ],
    ),
    if (hasImage)
      TargetFocus(
        identify: 'image',
        keyTarget: imageKey,
        shape: ShapeLightFocus.RRect,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            child: _content(
              loc.tutorialFlashcardImageTitle,
              isMultipleChoice
                  ? loc.tutorialFlashcardImageDescriptionMultipleChoice
                  : loc.tutorialFlashcardImageDescription,
            ),
          ),
        ],
      ),
    if (isMultipleChoice)
      TargetFocus(
        identify: 'options',
        keyTarget: optionsKey,
        shape: ShapeLightFocus.RRect,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            child: _content(
              loc.tutorialFlashcardOptionsTitle,
              loc.tutorialFlashcardOptionsDescription,
            ),
          ),
        ],
      )
    else ...[
      TargetFocus(
        identify: 'again',
        keyTarget: againKey,
        shape: ShapeLightFocus.RRect,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            child: _content(
              loc.flashcardButtonAgain,
              loc.tutorialFlashcardAgainDescription,
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: 'hard',
        keyTarget: hardKey,
        shape: ShapeLightFocus.RRect,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            child: _content(
              loc.flashcardButtonHard,
              loc.tutorialFlashcardHardDescription,
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: 'good',
        keyTarget: goodKey,
        shape: ShapeLightFocus.RRect,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            child: _content(
              loc.flashcardButtonGood,
              loc.tutorialFlashcardGoodDescription,
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: 'easy',
        keyTarget: easyKey,
        shape: ShapeLightFocus.RRect,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            child: _content(
              loc.flashcardButtonEasy,
              loc.tutorialFlashcardEasyDescription,
            ),
          ),
        ],
      ),
    ],
    TargetFocus(
      identify: 'watchlist',
      keyTarget: watchlistButtonKey,
      shape: ShapeLightFocus.Circle,
      paddingFocus: 8,
      contents: [
        TargetContent(
          align: ContentAlign.bottom,
          child: _content(
            loc.tutorialFlashcardWatchlistTitle,
            loc.tutorialFlashcardWatchlistDescription,
          ),
        ),
      ],
    ),
  ];

  Widget _content(String title, String body) {
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
