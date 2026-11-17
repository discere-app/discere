import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/ui/coach_mark_tour.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

/// Builds and shows the first-run coach-mark tour over MainScreenPage's
/// deck-card favorite action, deck-card edit action, and the watchlist tab —
/// behaviors that aren't obvious from their icon alone. Pulled out of
/// MainScreenPage because the target list is a self-contained template —
/// MainScreenState only needs to decide *when* to show it.
class MainScreenTutorial {
  final GlobalKey deckFavKey;
  final GlobalKey deckEditKey;
  final GlobalKey watchlistKey;

  /// Whether to include the deckFav/watchlist steps and the announcing
  /// intro step. False for a user who already completed the original
  /// two-step tour (tracked by [UserPreferencesService.hasSeenTutorial]) —
  /// they only need the newer deckEdit step added later, shown on its own
  /// without replaying what they've already seen or re-announcing a "tour".
  final bool includePreviouslySeenSteps;

  const MainScreenTutorial({
    required this.deckFavKey,
    required this.deckEditKey,
    required this.watchlistKey,
    this.includePreviouslySeenSteps = true,
  });

  void show(BuildContext context) {
    showCoachMarkTour(context, targets: _targets(context, context.loc));
  }

  List<TargetFocus> _targets(BuildContext context, AppLocalizations loc) => [
    // No real widget is highlighted here — a zero-size target centered on
    // screen just gives the overlay text to show without a focus ring, so
    // the tour visibly announces itself as a tour before it starts pointing
    // at things (testers otherwise mistook the first coach mark for an
    // accidental tap/bug). Skipped when only the deckEdit step is being
    // shown on its own — there's no "tour" to announce for a single hint.
    if (includePreviouslySeenSteps)
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
              body: loc.tutorialIntroDescription,
            ),
          ),
        ],
      ),
    if (includePreviouslySeenSteps)
      TargetFocus(
        identify: 'deckFav',
        keyTarget: deckFavKey,
        shape: ShapeLightFocus.Circle,
        paddingFocus: 4,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            child: CoachMarkContent(
              title: loc.tutorialDeckFavTitle,
              body: loc.tutorialDeckFavDescription,
            ),
          ),
        ],
      ),
    TargetFocus(
      identify: 'deckEdit',
      keyTarget: deckEditKey,
      shape: ShapeLightFocus.Circle,
      paddingFocus: 4,
      contents: [
        TargetContent(
          align: ContentAlign.bottom,
          child: CoachMarkContent(
            title: loc.tutorialDeckEditTitle,
            body: loc.tutorialDeckEditDescription,
          ),
        ),
      ],
    ),
    if (includePreviouslySeenSteps)
      TargetFocus(
        identify: 'watchlist',
        keyTarget: watchlistKey,
        shape: ShapeLightFocus.Circle,
        paddingFocus: 16,
        // The watchlist tab sits bottom-right, right where the skip button
        // defaults to — move skip to the top for this step so the two
        // don't overlap and become unreadable/untappable.
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            child: CoachMarkContent(
              title: loc.tutorialWatchlistTitle,
              body: loc.tutorialWatchlistDescription,
            ),
          ),
        ],
      ),
  ];
}
