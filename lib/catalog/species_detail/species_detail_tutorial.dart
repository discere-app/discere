import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

/// Builds and shows the first-run coach mark over SpeciesDetailPage's
/// "add to deck" action — the single entry point for both creating a new
/// deck and adding the species to an existing one, which isn't obvious
/// from the icon alone. Pulled out of SpeciesDetailLoaderPage because the
/// target list is a self-contained template — the loader's state only
/// needs to decide *when* to show it.
class SpeciesDetailTutorial {
  final GlobalKey addToDeckKey;

  const SpeciesDetailTutorial({required this.addToDeckKey});

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
      identify: 'addToDeck',
      keyTarget: addToDeckKey,
      shape: ShapeLightFocus.Circle,
      paddingFocus: 4,
      contents: [
        TargetContent(
          align: ContentAlign.bottom,
          child: _content(
            loc.tutorialSpeciesDetailAddToDeckTitle,
            loc.tutorialSpeciesDetailAddToDeckDescription,
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
