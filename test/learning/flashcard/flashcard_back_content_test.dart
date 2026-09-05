import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/flashcard/flashcard_back_content.dart';
import 'package:discere/learning/flashcard/flip_swipe_detector.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Species _makeSpecies({
  Map<Language, List<String>> commonNames = const {
    Language.de: ['Weißer Hai'],
    Language.en: ['Great white shark'],
  },
}) {
  return Species(
    'sp1',
    'ext1',
    'fishbase',
    'carcharias',
    commonNames,
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

Widget _buildApp({
  bool namesMayStillRefine = false,
  Language language = Language.en,
  Map<Language, List<String>> commonNames = const {
    Language.de: ['Weißer Hai'],
    Language.en: ['Great white shark'],
  },
  FlashcardFlipController? flipController,
  required WatchlistService watchlistService,
}) {
  return ChangeNotifierProvider<WatchlistService>.value(
    value: watchlistService,
    child: MaterialApp(
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
          speciesWithLocalImages: SpeciesWithLocalImages(
            _makeSpecies(commonNames: commonNames),
            [],
          ),
          language: language,
          namesMayStillRefine: namesMayStillRefine,
          flipController: flipController,
        ),
      ),
    ),
  );
}

void main() {
  late WatchlistService watchlistService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    watchlistService = WatchlistService(await SharedPreferences.getInstance());
  });

  testWidgets('shows a watchlist button that adds/removes the species', (
    tester,
  ) async {
    await tester.pumpWidget(_buildApp(watchlistService: watchlistService));

    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
    expect(find.byIcon(Icons.bookmark), findsNothing);

    await tester.tap(find.byIcon(Icons.bookmark_border));
    await tester.pump();

    expect(watchlistService.getSpecies(), contains('sp1'));
    expect(find.byIcon(Icons.bookmark), findsOneWidget);

    await tester.tap(find.byIcon(Icons.bookmark));
    await tester.pump();

    expect(watchlistService.getSpecies(), isNot(contains('sp1')));
  });

  testWidgets(
    'positions the watchlist button top-right, matching the front, and the '
    'hint badge top-left so the two never overlap',
    (tester) async {
      // Checked structurally (which side each Positioned pins to) rather
      // than via screen geometry — this widget applies its own 180°
      // counter-rotation that only cancels out to "upright" once nested
      // under FlashcardWidget's matching outer rotation (absent when
      // pumping FlashcardBackContent standalone, as here), which would
      // otherwise make screen-space left/right assertions misleading.
      await tester.pumpWidget(
        _buildApp(namesMayStillRefine: true, watchlistService: watchlistService),
      );

      final watchlistPositioned = tester.widget<Positioned>(
        find
            .ancestor(
              of: find.byIcon(Icons.bookmark_border),
              matching: find.byType(Positioned),
            )
            .first,
      );
      final hintBadgePositioned = tester.widget<Positioned>(
        find
            .ancestor(
              of: find.byIcon(Icons.info_outline),
              matching: find.byType(Positioned),
            )
            .first,
      );

      expect(watchlistPositioned.right, AppSpacing.s12);
      expect(watchlistPositioned.left, isNull);
      expect(hintBadgePositioned.left, AppSpacing.s12);
      expect(hintBadgePositioned.right, isNull);
    },
  );

  testWidgets('shows no hint icon when the name is not pending enrichment '
      'and not an English fallback', (tester) async {
    await tester.pumpWidget(_buildApp(watchlistService: watchlistService));

    expect(find.byIcon(Icons.info_outline), findsNothing);
  });

  testWidgets(
    'shows a hint icon while common-name enrichment is still pending, '
    'opening an explainer dialog with only the refining text',
    (tester) async {
      await tester.pumpWidget(
        _buildApp(
          namesMayStillRefine: true,
          watchlistService: watchlistService,
        ),
      );

      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(find.text('About this name'), findsNothing);

      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();

      expect(find.text('About this name'), findsOneWidget);
      expect(
        find.text(
          'This name may still be refined as more data becomes available.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'No name in your language is available for this species yet, '
          'so the English name is shown instead.',
        ),
        findsNothing,
      );

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('About this name'), findsNothing);
    },
  );

  testWidgets(
    'shows a hint icon when the requested language has no common name and '
    'the primary name is an English fallback, with only the fallback text',
    (tester) async {
      await tester.pumpWidget(
        _buildApp(
          language: Language.de,
          commonNames: const {
            Language.en: ['Great white shark'],
          },
          watchlistService: watchlistService,
        ),
      );

      expect(find.byIcon(Icons.info_outline), findsOneWidget);

      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();

      expect(find.text('About this name'), findsOneWidget);
      expect(
        find.text(
          'This name may still be refined as more data becomes available.',
        ),
        findsNothing,
      );
      expect(
        find.text(
          'No name in your language is available for this species yet, '
          'so the English name is shown instead.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'shows both explanations when refining and the English fallback apply '
    'at once',
    (tester) async {
      await tester.pumpWidget(
        _buildApp(
          language: Language.de,
          namesMayStillRefine: true,
          commonNames: const {
            Language.en: ['Great white shark'],
          },
          watchlistService: watchlistService,
        ),
      );

      expect(find.byIcon(Icons.info_outline), findsOneWidget);

      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'This name may still be refined as more data becomes available.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'No name in your language is available for this species yet, '
          'so the English name is shown instead.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'tapping the hint icon does not also trigger the ambient '
    'tap-to-flip gesture underneath it',
    (tester) async {
      var flipped = false;
      await tester.pumpWidget(
        _buildApp(
          namesMayStillRefine: true,
          flipController: FlashcardFlipController(
            onTap: () => flipped = true,
            onDragStart: (_) {},
            onDragUpdate: (_, _) {},
            onDragEnd: () {},
          ),
          watchlistService: watchlistService,
        ),
      );

      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();

      expect(flipped, isFalse);
      expect(find.text('About this name'), findsOneWidget);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Sanity check: the rest of the back content is still flip-tappable —
      // the fix must exempt only the badge, not the whole back. Tap a point
      // well away from the top-right badge rather than a Text finder, since
      // CopyableText's animated style rebuild can transiently duplicate its
      // Text widget.
      await tester.tapAt(
        tester.getTopLeft(find.byType(FlashcardBackContent)) +
            const Offset(20, 150),
      );
      expect(flipped, isTrue);
    },
  );

  testWidgets(
    'shows the current language as a chip, and switching it in the menu '
    're-renders the name in that language for just this card',
    (tester) async {
      await tester.pumpWidget(
        _buildApp(language: Language.de, watchlistService: watchlistService),
      );

      expect(find.text('DE'), findsOneWidget);
      expect(find.text('Weißer Hai'), findsWidgets);

      await tester.tap(find.text('DE'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();

      expect(find.text('EN'), findsOneWidget);
      expect(find.text('DE'), findsNothing);
      expect(find.text('Great white shark'), findsWidgets);
    },
  );

  testWidgets(
    'leaves languages with no common name for this species out of the menu '
    'entirely, so picking one never silently lands on the English fallback',
    (tester) async {
      await tester.pumpWidget(
        _buildApp(
          language: Language.de,
          commonNames: const {
            Language.de: ['Weißer Hai'],
            Language.en: ['Great white shark'],
          },
          watchlistService: watchlistService,
        ),
      );

      await tester.tap(find.text('DE'));
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(PopupMenuItem<Language>, 'German'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(PopupMenuItem<Language>, 'English'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(PopupMenuItem<Language>, 'Spanish'),
        findsNothing,
      );
      expect(
        find.widgetWithText(PopupMenuItem<Language>, 'French'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'keeps the current language in the menu even when this species has no '
    'common name for it, so it never becomes unreachable once shown',
    (tester) async {
      await tester.pumpWidget(
        _buildApp(
          language: Language.de,
          commonNames: const {
            Language.en: ['Great white shark'],
          },
          watchlistService: watchlistService,
        ),
      );

      await tester.tap(find.text('DE'));
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(PopupMenuItem<Language>, 'German'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(PopupMenuItem<Language>, 'English'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(PopupMenuItem<Language>, 'Spanish'),
        findsNothing,
      );
      expect(
        find.widgetWithText(PopupMenuItem<Language>, 'French'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'tapping the language selector does not also trigger the ambient '
    'tap-to-flip gesture underneath it',
    (tester) async {
      var flipped = false;
      await tester.pumpWidget(
        _buildApp(
          flipController: FlashcardFlipController(
            onTap: () => flipped = true,
            onDragStart: (_) {},
            onDragUpdate: (_, _) {},
            onDragEnd: () {},
          ),
          watchlistService: watchlistService,
        ),
      );

      await tester.tap(find.text('EN'));
      await tester.pumpAndSettle();

      expect(flipped, isFalse);
    },
  );
}
