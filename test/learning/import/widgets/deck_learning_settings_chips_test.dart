import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/import/widgets/deck_learning_settings_chips.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/learning/model/review_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpChips(
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
          body: DeckLearningSettingsChips(
            learningMode: learningMode,
            nameType: nameType,
            reviewMode: reviewMode,
          ),
        ),
      ),
    );
  }

  List<String> chipLabels(WidgetTester tester) => tester
      .widgetList<Chip>(find.byType(Chip))
      .map((chip) => (chip.label as Text).data!)
      .toList();

  testWidgets('shows learning mode, name type and review mode in that order', (
    tester,
  ) async {
    await pumpChips(
      tester,
      learningMode: LearningMode.genus,
      nameType: NameType.scientificName,
      reviewMode: ReviewMode.multipleChoice,
    );

    expect(chipLabels(tester), ['Genus', 'Scientific Name', 'Multiple Choice']);
  });

  testWidgets('shows the default settings like any other', (tester) async {
    await pumpChips(
      tester,
      learningMode: LearningMode.species,
      nameType: NameType.commonName,
      reviewMode: ReviewMode.flip,
    );

    expect(chipLabels(tester), ['Species', 'Common Name', 'Flip Card']);
  });

  testWidgets('names the setting each value belongs to in its tooltip', (
    tester,
  ) async {
    await pumpChips(
      tester,
      learningMode: LearningMode.genus,
      nameType: NameType.scientificName,
      reviewMode: ReviewMode.multipleChoice,
    );

    expect(find.byTooltip('Learning Mode: Genus'), findsOneWidget);
    expect(find.byTooltip('Name Type: Scientific Name'), findsOneWidget);
    expect(find.byTooltip('Review Mode: Multiple Choice'), findsOneWidget);
  });
}
