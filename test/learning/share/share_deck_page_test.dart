import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/service/import_export_service.dart';
import 'package:discere/learning/share/share_deck_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../mocks.mocks.dart';

// Not pumpAndSettle: the loading state uses an indeterminate
// CircularProgressIndicator, which never "settles". The payload future
// resolves via two real Isolate.run calls — tester.pump() alone never lets
// those finish (it only drives the fake test clock/microtasks, not genuine
// isolate scheduling), so give them a real async window via runAsync first.
Future<void> _waitForLoad(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 500)),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockDecksService mockDecksService;
  late ImportExportService importExportService;

  setUp(() {
    mockDecksService = MockDecksService();
    importExportService = ImportExportService(mockDecksService);
  });

  Widget buildApp(String deckId) {
    return MultiProvider(
      providers: [
        Provider<ImportExportService>.value(value: importExportService),
      ],
      child: MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: ShareDeckPage(deck: BaseDeck(deckId, 'Test Deck', 'desc')),
      ),
    );
  }

  testWidgets('shows the QR code for a deck within QR capacity', (
    tester,
  ) async {
    when(mockDecksService.getCreateDeck('deck-small')).thenAnswer(
      (_) async => CreateDeck(
        name: 'Test Deck',
        description: 'desc',
        speciesNames: {'Genus species'},
      ),
    );

    await tester.pumpWidget(buildApp('deck-small'));
    await _waitForLoad(tester);

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.byKey(const Key('share_qr_too_large_warning')), findsNothing);
    expect(find.byKey(const Key('share_qr_dense_warning')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'shows a dense-code warning alongside a still-valid QR code',
    (tester) async {
      // Comfortably past the dense-module-count threshold (117) but well
      // within the hard QR capacity — still encodes fine, just tightly.
      final manySpeciesNames = {
        for (var i = 0; i < 400; i++) 'Genus$i species$i',
      };
      when(mockDecksService.getCreateDeck('deck-dense')).thenAnswer(
        (_) async => CreateDeck(
          name: 'Test Deck',
          description: 'desc',
          speciesNames: manySpeciesNames,
        ),
      );

      await tester.pumpWidget(buildApp('deck-dense'));
      await _waitForLoad(tester);

      expect(find.byType(QrImageView), findsOneWidget);
      expect(
        find.byKey(const Key('share_qr_dense_warning')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('share_qr_too_large_warning')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shows a warning instead of crashing for a deck too large for a QR code',
    (tester) async {
      // Well past the QR version-40/error-correction-L capacity (~2.9KB
      // gzip+base64 payload) so this reliably exercises the too-large path
      // rather than sitting near the boundary.
      final manySpeciesNames = {
        for (var i = 0; i < 1500; i++) 'Genus$i species$i',
      };
      when(mockDecksService.getCreateDeck('deck-huge')).thenAnswer(
        (_) async => CreateDeck(
          name: 'Test Deck',
          description: 'desc',
          speciesNames: manySpeciesNames,
        ),
      );

      await tester.pumpWidget(buildApp('deck-huge'));
      await _waitForLoad(tester);

      expect(
        find.byKey(const Key('share_qr_too_large_warning')),
        findsOneWidget,
      );
      expect(find.byType(QrImageView), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
