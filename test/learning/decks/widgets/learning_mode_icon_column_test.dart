import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/decks/widgets/learning_mode_icon_column.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/learning/model/review_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LearningModeIconColumn.hasNonDefault', () {
    test('is false for the defaults a new deck starts with', () {
      expect(
        LearningModeIconColumn.hasNonDefault(
          learningMode: DeckConfig.defaultLearningMode,
          nameType: DeckConfig.defaultNameType,
          reviewMode: DeckConfig.defaultReviewMode,
        ),
        isFalse,
      );
    });

    test('is true as soon as one setting differs', () {
      for (final (learningMode, nameType, reviewMode) in [
        (
          LearningMode.genus,
          DeckConfig.defaultNameType,
          DeckConfig.defaultReviewMode,
        ),
        (
          DeckConfig.defaultLearningMode,
          NameType.scientificName,
          DeckConfig.defaultReviewMode,
        ),
        (
          DeckConfig.defaultLearningMode,
          DeckConfig.defaultNameType,
          ReviewMode.multipleChoice,
        ),
      ]) {
        expect(
          LearningModeIconColumn.hasNonDefault(
            learningMode: learningMode,
            nameType: nameType,
            reviewMode: reviewMode,
          ),
          isTrue,
          reason: '$learningMode / $nameType / $reviewMode',
        );
      }
    });
  });

  testWidgets('shows an icon only for the settings that differ from the '
      'defaults', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: LearningModeIconColumn(
            learningMode: DeckConfig.defaultLearningMode,
            nameType: NameType.scientificName,
            reviewMode: DeckConfig.defaultReviewMode,
          ),
        ),
      ),
    );

    expect(
      tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((tooltip) => tooltip.message),
      ['Scientific Name'],
    );
  });
}
