import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/ui/coach_mark_tour.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

/// Builds and shows the first-run coach marks over EditDeckPage: the
/// learning settings section — the only place a deck's learning mode
/// (species/genus/family), name type, and review mode (flip/multiple
/// choice) can be changed, which isn't obvious from the edit screen alone —
/// and the subdeck section, where a deck is divided and parts of it switched
/// off. Pulled out of EditDeckPage because the target list is a self-contained template —
/// the page's state only needs to decide *when* to show it, and which
/// steps.
///
/// A step whose key is null is left out: each has its own "seen" flag, so a
/// user who has already seen the learning settings step gets only the subdeck
/// step.
class EditDeckTutorial {
  final GlobalKey? learningSettingsKey;
  final GlobalKey? subdecksKey;

  const EditDeckTutorial({this.learningSettingsKey, this.subdecksKey});

  void show(BuildContext context) {
    showCoachMarkTour(
      context,
      targets: _targets(context.loc),
      beforeFocus: _scrollIntoView,
    );
  }

  /// Both sections sit below the fold on smaller screens.
  Future<void> _scrollIntoView(TargetFocus target) async {
    final targetContext = target.keyTarget?.currentContext;
    if (targetContext == null || !targetContext.mounted) return;
    await Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 300),
      alignment: 0.1,
    );
  }

  List<TargetFocus> _targets(AppLocalizations loc) => [
    if (learningSettingsKey != null)
      TargetFocus(
        identify: 'learningSettings',
        keyTarget: learningSettingsKey,
        shape: ShapeLightFocus.RRect,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            child: CoachMarkContent(
              title: loc.tutorialEditDeckLearningSettingsTitle,
              body: loc.tutorialEditDeckLearningSettingsDescription,
            ),
          ),
        ],
      ),
    if (subdecksKey != null)
      TargetFocus(
        identify: 'subdecks',
        keyTarget: subdecksKey,
        shape: ShapeLightFocus.RRect,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            child: CoachMarkContent(
              title: loc.tutorialEditDeckSubdecksTitle,
              body: loc.tutorialEditDeckSubdecksDescription,
            ),
          ),
        ],
      ),
  ];
}
