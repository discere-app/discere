import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

/// Builds and shows the first-run coach mark over EditDeckPage's learning
/// settings section — the only place a deck's learning mode (species/genus/
/// family), name type, and review mode (flip/multiple choice) can be
/// changed, which isn't obvious from the edit screen alone. Pulled out of
/// EditDeckPage because the target list is a self-contained template —
/// the page's state only needs to decide *when* to show it.
class EditDeckTutorial {
  final GlobalKey learningSettingsKey;

  const EditDeckTutorial({required this.learningSettingsKey});

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
      identify: 'learningSettings',
      keyTarget: learningSettingsKey,
      shape: ShapeLightFocus.RRect,
      contents: [
        TargetContent(
          align: ContentAlign.bottom,
          child: _content(
            loc.tutorialEditDeckLearningSettingsTitle,
            loc.tutorialEditDeckLearningSettingsDescription,
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
