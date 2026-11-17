import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/ui/coach_mark_tour.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

/// Builds and shows the first-run coach marks over SpeciesDetailPage's
/// "add to deck" action — the single entry point for both creating a new
/// deck and adding the species to an existing one, which isn't obvious
/// from the icon alone — and its "add to comparison" action. Pulled out of
/// SpeciesDetailLoaderPage because the target list is a self-contained
/// template — the loader's state only needs to decide *when* to show it, and
/// which steps.
///
/// A step whose key is null is left out: each has its own "seen" flag, so a
/// user who has already seen the "add to deck" step gets only the comparison
/// step.
class SpeciesDetailTutorial {
  final GlobalKey? addToDeckKey;
  final GlobalKey? compareKey;

  const SpeciesDetailTutorial({this.addToDeckKey, this.compareKey});

  void show(BuildContext context) {
    showCoachMarkTour(context, targets: _targets(context.loc));
  }

  List<TargetFocus> _targets(AppLocalizations loc) => [
    if (addToDeckKey case final key?)
      _target(
        'addToDeck',
        key,
        loc.tutorialSpeciesDetailAddToDeckTitle,
        loc.tutorialSpeciesDetailAddToDeckDescription,
      ),
    if (compareKey case final key?)
      _target(
        'compare',
        key,
        loc.tutorialSpeciesDetailCompareTitle,
        loc.tutorialSpeciesDetailCompareDescription,
      ),
  ];

  /// A step over the app bar action [key].
  TargetFocus _target(
    String identify,
    GlobalKey key,
    String title,
    String body,
  ) {
    return TargetFocus(
      identify: identify,
      keyTarget: key,
      shape: ShapeLightFocus.Circle,
      paddingFocus: 4,
      contents: [
        TargetContent(
          align: ContentAlign.bottom,
          child: CoachMarkContent(title: title, body: body),
        ),
      ],
    );
  }
}
