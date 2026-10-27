import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/import/import_online_deck_list_tile.dart';
import 'package:discere/learning/import/import_online_deck_presenter.dart';
import 'package:discere/learning/import/widgets/deck_learning_settings_icons.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/review_mode.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpTile(
    WidgetTester tester,
    CreateDeck deck, {
    ImportOnlineDeckStatus status = ImportOnlineDeckStatus.notImported,
    ValueChanged<bool?>? onSelected,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ImportOnlineDeckListTile(
            deck: deck,
            status: status,
            isSelected: false,
            isExpanded: false,
            selectedLanguage: Language.en,
            onSelected: onSelected ?? (_) {},
            onLanguageChanged: (_) {},
            onToggleExpanded: () {},
          ),
        ),
      ),
    );
  }

  List<String> settingTooltips(WidgetTester tester) => tester
      .widgetList<Tooltip>(
        find.descendant(
          of: find.byType(DeckLearningSettingsIcons),
          matching: find.byType(Tooltip),
        ),
      )
      .map((tooltip) => tooltip.message!)
      .toList();

  CreateDeck deckWithSettings() => CreateDeck(
    name: 'Reef genera',
    description: '',
    speciesNames: {'Amphiprion ocellaris'},
    learningMode: LearningMode.genus,
    reviewMode: ReviewMode.multipleChoice,
  );

  testWidgets(
    'an entry to import shows its learning settings, with the default for '
    'the one it leaves open',
    (tester) async {
      await pumpTile(tester, deckWithSettings());

      expect(settingTooltips(tester), [
        'Learning Mode: Genus',
        'Name Type: Common Name',
        'Review Mode: Multiple Choice',
      ]);
    },
  );

  testWidgets('an entry without learning settings shows the defaults', (
    tester,
  ) async {
    await pumpTile(
      tester,
      CreateDeck(
        name: 'Reef fish',
        description: '',
        speciesNames: {'Amphiprion ocellaris'},
      ),
    );

    expect(settingTooltips(tester), [
      'Learning Mode: Species',
      'Name Type: Common Name',
      'Review Mode: Flip Card',
    ]);
  });

  testWidgets('tapping a learning setting selects the entry like the rest of '
      'the tile', (tester) async {
    bool? selected;
    await pumpTile(
      tester,
      deckWithSettings(),
      onSelected: (value) => selected = value,
    );

    await tester.tap(find.byTooltip('Learning Mode: Genus'));

    expect(selected, isTrue);
  });

  for (final status in [
    ImportOnlineDeckStatus.upToDate,
    ImportOnlineDeckStatus.updateAvailable,
    ImportOnlineDeckStatus.supersedesLocal,
  ]) {
    testWidgets(
      'shows no learning settings for an entry that is ${status.name}, '
      'since the local deck config applies',
      (tester) async {
        await pumpTile(tester, deckWithSettings(), status: status);

        expect(find.byType(DeckLearningSettingsIcons), findsNothing);
      },
    );
  }
}
