import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/flashcard/flashcard_front.dart';
import 'package:discere/learning/flashcard/flip_swipe_detector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Covers where FlashcardFront puts the flip-fallback notice: each of its
/// three layouts (portrait, landscape, no photo) builds its own footer or
/// side column, so each has to carry the notice on its own.

const _notice = 'Too few answer options – this card is flipped instead.';

SpeciesWithLocalImages _card({required bool withImage}) =>
    SpeciesWithLocalImages(
      Species(
        'sp1',
        'sp1',
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
      [
        if (withImage)
          LocalPicture(
            Picture(
              id: 'pic1',
              species: 'sp1',
              origin: 'fishbase',
              isUsable: 1,
            ),
            '1.jpg',
          ),
      ],
    );

void main() {
  late WatchlistService watchlistService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    watchlistService = WatchlistService(await SharedPreferences.getInstance());
  });

  Future<void> pumpFront(
    WidgetTester tester, {
    required bool isFlipFallback,
    bool withImage = true,
    Size size = const Size(400, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<WatchlistService>.value(
        value: watchlistService,
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: FlashcardFront(
              speciesWithLocalImages: _card(withImage: withImage),
              flipController: FlashcardFlipController(
                onTap: () {},
                onDragStart: (_) {},
                onDragUpdate: (_, _) {},
                onDragEnd: () {},
              ),
              isFlipFallback: isFlipFallback,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('portrait shows the notice above the tap hint', (tester) async {
    await pumpFront(tester, isFlipFallback: true);

    expect(find.text(_notice), findsOneWidget);
  });

  testWidgets(
    'landscape shows the notice in a side column, even without size or '
    'depth hints to share it with',
    (tester) async {
      await pumpFront(tester, isFlipFallback: true, size: const Size(800, 400));

      expect(find.text(_notice), findsOneWidget);
    },
  );

  testWidgets('a card without a photo shows the notice too', (tester) async {
    await pumpFront(tester, isFlipFallback: true, withImage: false);

    expect(find.text(_notice), findsOneWidget);
  });

  testWidgets('a card asked by flipping by design shows no notice', (
    tester,
  ) async {
    await pumpFront(tester, isFlipFallback: false);

    expect(find.text(_notice), findsNothing);
  });
}
