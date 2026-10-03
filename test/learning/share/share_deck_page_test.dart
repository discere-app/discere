import 'dart:io';

import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/share/deck_export_service.dart';
import 'package:discere/learning/share/share_deck_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  late DeckExportService deckExportService;
  late Future<Uri?> Function() saveDialogAnswer;
  late int saveDialogCalls;

  setUp(() {
    mockDecksService = MockDecksService();
    saveDialogAnswer = () async => null;
    saveDialogCalls = 0;
    deckExportService = DeckExportService(
      mockDecksService,
      fileSaver: ({required fileName, required bytes, required mimeType}) {
        saveDialogCalls++;
        return saveDialogAnswer();
      },
    );
  });

  Widget buildApp(String deckId) {
    return MultiProvider(
      providers: [
        Provider<DeckExportService>.value(value: deckExportService),
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
        home: ShareDeckPage(deck: BaseDeck(id: deckId, name: 'Test Deck', description: 'desc')),
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

  group('JSON file export', () {
    const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
    const pathProviderChannel = MethodChannel(
      'plugins.flutter.io/path_provider',
    );
    late Directory tempDir;
    late List<MethodCall> shareCalls;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('share_deck_page_test');
      shareCalls = [];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(shareChannel, (call) async {
        shareCalls.add(call);
        return 'dev.fluttercommunity.plus/share/unavailable';
      });
      messenger.setMockMethodCallHandler(
        pathProviderChannel,
        (call) async => tempDir.path,
      );
      when(mockDecksService.getCreateDeck('deck-export')).thenAnswer(
        (_) async => CreateDeck(
          name: 'Test Deck',
          description: 'desc',
          speciesNames: {'Genus species'},
        ),
      );
    });

    tearDown(() async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(shareChannel, null);
      messenger.setMockMethodCallHandler(pathProviderChannel, null);
      await tempDir.delete(recursive: true);
    });

    // The share-sheet fallback writes a real temp file first, which only
    // completes outside the fake test clock — hence runAsync around the tap.
    Future<void> tapExport(WidgetTester tester) async {
      await tester.pumpWidget(buildApp('deck-export'));
      await _waitForLoad(tester);
      final exportOption = find.byKey(const Key('share_download_json_option'));
      await tester.ensureVisible(exportOption);
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(exportOption);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
    }

    // Lets the snackbar and the delayed reset to idle run out, so no timer
    // is still pending when the test ends.
    Future<void> settleTimers(WidgetTester tester) =>
        tester.pump(const Duration(seconds: 5));

    testWidgets('confirms the save once the dialog has written the file', (
      tester,
    ) async {
      saveDialogAnswer = () async => Uri.parse('content://downloads/1');

      await tapExport(tester);

      expect(find.text('Deck saved'), findsOneWidget);
      expect(shareCalls, isEmpty);
      await settleTimers(tester);
    });

    testWidgets('does nothing when the user cancels the save dialog', (
      tester,
    ) async {
      saveDialogAnswer = () async => null;

      await tapExport(tester);

      expect(saveDialogCalls, 1);
      expect(find.byType(SnackBar), findsNothing);
      expect(shareCalls, isEmpty);
      await settleTimers(tester);
    });

    testWidgets('falls back to the share sheet when saving fails', (
      tester,
    ) async {
      saveDialogAnswer = () async =>
          throw PlatformException(code: 'Error while saving file');

      await tapExport(tester);

      expect(shareCalls, hasLength(1));
      expect(find.byType(SnackBar), findsNothing);
      await settleTimers(tester);
    });
  });
}
