import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/ui/coach_mark_tour.dart';
import 'package:material_ui/material_ui.dart';
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
    showCoachMarkTour(
      context,
      targets: _targets(context, context.loc),
      // Every step's content sits in the lower half of the card (rating
      // buttons/options, image caption), so the default bottom-right skip
      // button would sit on top of them — move it to the top instead.
      alignSkip: Alignment.topRight,
    );
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
          child: CoachMarkContent(
            title: loc.tutorialIntroTitle,
            body: _introDescription(loc),
          ),
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
            child: CoachMarkContent(
              title: loc.tutorialFlashcardImageTitle,
              body: isMultipleChoice
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
            child: CoachMarkContent(
              title: loc.tutorialFlashcardOptionsTitle,
              body: loc.tutorialFlashcardOptionsDescription,
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
            child: CoachMarkContent(
              title: loc.flashcardButtonAgain,
              body: loc.tutorialFlashcardAgainDescription,
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
            child: CoachMarkContent(
              title: loc.flashcardButtonHard,
              body: loc.tutorialFlashcardHardDescription,
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
            child: CoachMarkContent(
              title: loc.flashcardButtonGood,
              body: loc.tutorialFlashcardGoodDescription,
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
            child: CoachMarkContent(
              title: loc.flashcardButtonEasy,
              body: loc.tutorialFlashcardEasyDescription,
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
          child: CoachMarkContent(
            title: loc.tutorialFlashcardWatchlistTitle,
            body: loc.tutorialFlashcardWatchlistDescription,
          ),
        ),
      ],
    ),
  ];
}
