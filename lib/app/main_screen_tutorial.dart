import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

/// Builds and shows the first-run coach-mark tour over MainScreenPage's
/// deck-card actions, search, and bottom-nav tabs. Pulled out of
/// MainScreenPage because the target list is a large, self-contained
/// template — MainScreenState only needs to decide *when* to show it.
class MainScreenTutorial {
  final GlobalKey deckFavKey;
  final GlobalKey deckEditKey;
  final GlobalKey deckShareKey;
  final GlobalKey searchKey;
  final GlobalKey favKey;
  final GlobalKey watchlistKey;

  const MainScreenTutorial({
    required this.deckFavKey,
    required this.deckEditKey,
    required this.deckShareKey,
    required this.searchKey,
    required this.favKey,
    required this.watchlistKey,
  });

  void show(BuildContext context) {
    final loc = context.loc;
    TutorialCoachMark(
      targets: _targets(loc),
      colorShadow: Colors.black,
      opacityShadow: 0.85,
      paddingFocus: 8,
      textSkip: loc.tutorialSkip,
      onSkip: () => true,
    ).show(context: context);
  }

  List<TargetFocus> _targets(AppLocalizations loc) => [
    TargetFocus(
      identify: 'deckFav',
      keyTarget: deckFavKey,
      shape: ShapeLightFocus.Circle,
      paddingFocus: 4,
      contents: [
        TargetContent(
          align: ContentAlign.bottom,
          child: _content(loc.tutorialDeckFavTitle, loc.tutorialDeckFavDescription),
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
      identify: 'deckShare',
      keyTarget: deckShareKey,
      shape: ShapeLightFocus.Circle,
      paddingFocus: 4,
      contents: [
        TargetContent(
          align: ContentAlign.bottom,
          child: _content(
            loc.tutorialDeckShareTitle,
            loc.tutorialDeckShareDescription,
          ),
        ),
      ],
    ),
    TargetFocus(
      identify: 'search',
      keyTarget: searchKey,
      shape: ShapeLightFocus.Circle,
      contents: [
        TargetContent(
          align: ContentAlign.bottom,
          child: _content(loc.tutorialSearchTitle, loc.tutorialSearchDescription),
        ),
      ],
    ),
    TargetFocus(
      identify: 'fav',
      keyTarget: favKey,
      shape: ShapeLightFocus.Circle,
      paddingFocus: 16,
      contents: [
        TargetContent(
          align: ContentAlign.top,
          child: _content(loc.tutorialFavTitle, loc.tutorialFavDescription),
        ),
      ],
    ),
    TargetFocus(
      identify: 'watchlist',
      keyTarget: watchlistKey,
      shape: ShapeLightFocus.Circle,
      paddingFocus: 16,
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
