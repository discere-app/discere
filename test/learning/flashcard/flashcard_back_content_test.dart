import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/flashcard/flashcard_back_content.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Species _makeSpecies() {
  return Species(
    'sp1',
    'ext1',
    'fishbase',
    'carcharias',
    const {
      Language.de: ['Weißer Hai'],
      Language.en: ['Great white shark'],
    },
    Classification(
      'Carcharodon',
      const {},
      null,
      'Lamnidae',
      const {},
      'Lamniformes',
      const {},
      'Chondrichthyes',
      const {},
      null,
    ),
    const [],
  );
}

Widget _buildApp({required bool namesMayStillRefine}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: FlashcardBackContent(
        speciesWithLocalImages: SpeciesWithLocalImages(_makeSpecies(), []),
        language: Language.en,
        namesMayStillRefine: namesMayStillRefine,
      ),
    ),
  );
}

void main() {
  testWidgets('shows no hint icon when the name is not pending enrichment', (
    tester,
  ) async {
    await tester.pumpWidget(_buildApp(namesMayStillRefine: false));

    expect(find.byIcon(Icons.info_outline), findsNothing);
  });

  testWidgets(
    'shows a hint icon next to the primary name while common-name '
    'enrichment is still pending, opening an explainer dialog on tap',
    (tester) async {
      await tester.pumpWidget(_buildApp(namesMayStillRefine: true));

      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(find.text('Name still loading'), findsNothing);

      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();

      expect(find.text('Name still loading'), findsOneWidget);
      expect(
        find.text(
          'This name may still be refined as more data becomes available.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('Name still loading'), findsNothing);
    },
  );
}
