import 'dart:async';

import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

// tutorial_coach_mark wraps its overlay in a `Material` of the Flutter SDK,
// whose default text style comes from the SDK's `Theme` — a theme the app
// never sets, since the app's theme lives in material_ui. Every text style in
// a tour is therefore derived explicitly from the app's theme here, rather
// than inherited from that default, so the tour keeps the app's typography.

/// Shows a first-run coach-mark tour over [targets], with the overlay, focus
/// padding and skip button every tour of the app shares.
///
/// [alignSkip] moves the skip button away from content it would cover;
/// [beforeFocus] runs before each step is highlighted, e.g. to scroll its
/// target into view.
void showCoachMarkTour(
  BuildContext context, {
  required List<TargetFocus> targets,
  AlignmentGeometry alignSkip = Alignment.bottomRight,
  FutureOr<void> Function(TargetFocus)? beforeFocus,
}) {
  TutorialCoachMark(
    targets: targets,
    colorShadow: Colors.black,
    opacityShadow: 0.85,
    paddingFocus: 8,
    textSkip: context.loc.tutorialSkip,
    textStyleSkip: _bodyStyle(context),
    alignSkip: alignSkip,
    onSkip: () => true,
    beforeFocus: beforeFocus,
  ).show(context: context);
}

/// The title and description of one coach-mark step, in white on the tour's
/// dark overlay.
class CoachMarkContent extends StatelessWidget {
  final String title;
  final String body;

  const CoachMarkContent({required this.title, required this.body, super.key});

  @override
  Widget build(BuildContext context) {
    final bodyStyle = _bodyStyle(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: bodyStyle.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(body, style: bodyStyle),
        ],
      ),
    );
  }
}

TextStyle _bodyStyle(BuildContext context) => Theme.of(
  context,
).textTheme.bodyMedium!.copyWith(color: Colors.white, fontSize: 14);
