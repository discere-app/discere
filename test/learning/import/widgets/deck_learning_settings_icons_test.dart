import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/decks/learning_mode_style.dart';
import 'package:discere/learning/import/widgets/deck_learning_settings_icons.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/learning/model/review_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const style = LearningModeStyle();

  Future<void> pumpIcons(
    WidgetTester tester, {
    required LearningMode learningMode,
    required NameType nameType,
    required ReviewMode reviewMode,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: DeckLearningSettingsIcons(
            learningMode: learningMode,
            nameType: nameType,
            reviewMode: reviewMode,
          ),
        ),
      ),
    );
  }

  List<String> tooltips(WidgetTester tester) => tester
      .widgetList<Tooltip>(find.byType(Tooltip))
      .map((tooltip) => tooltip.message!)
      .toList();

  List<IconData> icons(WidgetTester tester) => tester
      .widgetList<Icon>(find.byType(Icon))
      .map((icon) => icon.icon!)
      .toList();

  testWidgets(
    'shows learning mode, name type and review mode in that order, each '
    'named with its setting',
    (tester) async {
      await pumpIcons(
        tester,
        learningMode: LearningMode.genus,
        nameType: NameType.scientificName,
        reviewMode: ReviewMode.multipleChoice,
      );

      expect(tooltips(tester), [
        'Learning Mode: Genus',
        'Name Type: Scientific Name',
        'Review Mode: Multiple Choice',
      ]);
      expect(icons(tester), [
        style.iconFor(LearningMode.genus),
        style.nameTypeIconFor(NameType.scientificName),
        style.reviewModeIconFor(ReviewMode.multipleChoice),
      ]);
    },
  );

  testWidgets('shows the default settings like any other', (tester) async {
    await pumpIcons(
      tester,
      learningMode: LearningMode.species,
      nameType: NameType.commonName,
      reviewMode: ReviewMode.flip,
    );

    expect(tooltips(tester), [
      'Learning Mode: Species',
      'Name Type: Common Name',
      'Review Mode: Flip Card',
    ]);
    expect(icons(tester), [
      style.iconFor(LearningMode.species),
      style.nameTypeIconFor(NameType.commonName),
      style.reviewModeIconFor(ReviewMode.flip),
    ]);
  });
}
