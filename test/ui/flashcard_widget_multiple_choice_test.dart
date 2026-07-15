import 'dart:async';

import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/flashcard/flashcard_widget.dart';
import 'package:discere/learning/flashcard/multiple_choice_option.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

SpeciesWithLocalImages _speciesWithImages(String id) {
  return SpeciesWithLocalImages(
    Species(
      id,
      id,
      'fishbase',
      'species',
      const {},
      Classification(
        'Genus',
        const {},
        null,
        'Family',
        const {},
        'Order',
        const {},
        'Class',
        const {},
        null,
      ),
      const [],
    ),
    const [],
  );
}

const _options = [
  MultipleChoiceOption(label: 'Correct Name', isCorrect: true),
  MultipleChoiceOption(label: 'Wrong A', isCorrect: false),
  MultipleChoiceOption(label: 'Wrong B', isCorrect: false),
  MultipleChoiceOption(label: 'Wrong C', isCorrect: false),
];

Widget _buildApp(Widget home, WatchlistService watchlistService) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<WatchlistService>.value(value: watchlistService),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: home),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WatchlistService watchlistService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    watchlistService = WatchlistService(await SharedPreferences.getInstance());
  });

  testWidgets(
    'tapping the correct option reports isCorrect=true and reveals the '
    'Continue button after the delay',
    (tester) async {
      bool? reportedCorrect;
      bool continuePressed = false;

      await tester.pumpWidget(
        _buildApp(
          FlashcardWidget(
            speciesWithLocalImage: _speciesWithImages('sp1'),
            language: Language.en,
            reviewMode: ReviewMode.multipleChoice,
            multipleChoiceOptions: _options,
            onMultipleChoiceAnswered: (isCorrect) async {
              reportedCorrect = isCorrect;
            },
            onContinue: () => continuePressed = true,
          ),
          watchlistService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Correct Name'));
      await tester.pump();

      expect(reportedCorrect, isTrue);

      // Continue button not visible yet — reveal is still pending.
      expect(find.text('Continue'), findsNothing);

      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      expect(find.text('Continue'), findsOneWidget);

      await tester.tap(find.text('Continue'));
      await tester.pump();

      expect(continuePressed, isTrue);
    },
  );

  testWidgets(
    'tapping a wrong option reports isCorrect=false and a second tap is a '
    'no-op',
    (tester) async {
      final reportedAnswers = <bool>[];

      await tester.pumpWidget(
        _buildApp(
          FlashcardWidget(
            speciesWithLocalImage: _speciesWithImages('sp1'),
            language: Language.en,
            reviewMode: ReviewMode.multipleChoice,
            multipleChoiceOptions: _options,
            onMultipleChoiceAnswered: (isCorrect) async {
              reportedAnswers.add(isCorrect);
            },
            onContinue: () {},
          ),
          watchlistService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Wrong A'));
      await tester.pump();

      expect(reportedAnswers, [false]);

      // A second tap on another option before the reveal must be ignored.
      await tester.tap(find.text('Wrong B'));
      await tester.pump();

      expect(reportedAnswers, [false]);
    },
  );

  testWidgets(
    'Continue waits for a still-pending grading call before firing onContinue',
    (tester) async {
      final gradingCompleter = Completer<void>();
      bool continuePressed = false;

      await tester.pumpWidget(
        _buildApp(
          FlashcardWidget(
            speciesWithLocalImage: _speciesWithImages('sp1'),
            language: Language.en,
            reviewMode: ReviewMode.multipleChoice,
            multipleChoiceOptions: _options,
            onMultipleChoiceAnswered: (isCorrect) => gradingCompleter.future,
            onContinue: () => continuePressed = true,
          ),
          watchlistService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Correct Name'));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      expect(find.text('Continue'), findsOneWidget);

      await tester.tap(find.text('Continue'));
      await tester.pump();

      // Grading is still pending — onContinue must not have fired yet.
      expect(continuePressed, isFalse);

      gradingCompleter.complete();
      await tester.pump();

      expect(continuePressed, isTrue);
    },
  );
}
