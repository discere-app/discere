import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
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

  const MainScreenTutorial({
    required this.deckFavKey,
    required this.deckEditKey,
    required this.watchlistKey,
  });

  void show(BuildContext context) {
    final loc = context.loc;
    TutorialCoachMark(
      targets: _targets(context, loc),
      colorShadow: Colors.black,
      opacityShadow: 0.85,
      paddingFocus: 8,
      textSkip: loc.tutorialSkip,
      onSkip: () => true,
    ).show(context: context);
  }

  List<TargetFocus> _targets(BuildContext context, AppLocalizations loc) => [
    // No real widget is highlighted here — a zero-size target centered on
    // screen just gives the overlay text to show without a focus ring, so
    // the tour visibly announces itself as a tour before it starts pointing
    // at things (testers otherwise mistook the first coach mark for an
    // accidental tap/bug).
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
          child: _content(loc.tutorialIntroTitle, loc.tutorialIntroDescription),
        ),
      ],
    ),
    TargetFocus(
      identify: 'deckFav',
      keyTarget: deckFavKey,
      shape: ShapeLightFocus.Circle,
      paddingFocus: 4,
      contents: [
        TargetContent(
          align: ContentAlign.bottom,
          child: _content(
            loc.tutorialDeckFavTitle,
            loc.tutorialDeckFavDescription,
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
          child: _content(
            loc.tutorialDeckEditTitle,
            loc.tutorialDeckEditDescription,
          ),
        ),
      ],
    ),
    TargetFocus(
      identify: 'watchlist',
      keyTarget: watchlistKey,
      shape: ShapeLightFocus.Circle,
      paddingFocus: 16,
      // The watchlist tab sits bottom-right, right where the skip button
      // defaults to — move skip to the top for this step so the two don't
      // overlap and become unreadable/untappable.
      alignSkip: Alignment.topRight,
      contents: [
        TargetContent(
          align: ContentAlign.top,
          child: _content(
            loc.tutorialWatchlistTitle,
            loc.tutorialWatchlistDescription,
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
