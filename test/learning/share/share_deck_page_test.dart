import 'dart:io';

import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/share/deck_export_service.dart';
import 'package:discere/learning/share/share_deck_page.dart';
import 'package:discere/learning/share/widgets/qr_code_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../mocks.mocks.dart';
import '../../support/pump_until.dart';

// Not pumpAndSettle: the loading state uses an indeterminate
// CircularProgressIndicator, which never "settles". The payload future
// resolves via two real Isolate.run calls — tester.pump() alone never lets
// those finish (it only drives the fake test clock/microtasks, not genuine
// isolate scheduling), so this pumps in real time until the page shows its
// QR section: the code, or the warning that the deck is too large for one.
Future<void> _waitForLoad(WidgetTester tester) async {
  await tester.runAsync(
    () => pumpUntil(
      tester,
      () =>
          find.byType(QrCodeView).evaluate().isNotEmpty ||
          find
              .byKey(const Key('share_qr_too_large_warning'))
              .evaluate()
              .isNotEmpty,
      reason: 'the share payload to load',
    ),
  );
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

    expect(find.byType(QrCodeView), findsOneWidget);
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

      expect(find.byType(QrCodeView), findsOneWidget);
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
      expect(find.byType(QrCodeView), findsNothing);
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
    // completes outside the fake test clock — hence pumping in real time
    // around the tap, until [done] says the export has come to its end.
    Future<void> tapExport(
      WidgetTester tester, {
      required bool Function() done,
      required String reason,
    }) async {
      await tester.pumpWidget(buildApp('deck-export'));
      await _waitForLoad(tester);
      final exportOption = find.byKey(const Key('share_download_json_option'));
      await tester.ensureVisible(exportOption);
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(exportOption);
        await pumpUntil(tester, done, reason: reason);
      });
    }

    /// The export option is ready again: its idle icon is back.
    bool exportIdle() => find
        .descendant(
          of: find.byKey(const Key('share_download_json_option')),
          matching: find.byKey(const ValueKey('idle')),
        )
        .evaluate()
        .isNotEmpty;

    // Lets the snackbar and the delayed reset to idle run out, so no timer
    // is still pending when the test ends.
    Future<void> settleTimers(WidgetTester tester) =>
        tester.pump(const Duration(seconds: 5));

    testWidgets('confirms the save once the dialog has written the file', (
      tester,
    ) async {
      saveDialogAnswer = () async => Uri.parse('content://downloads/1');

      await tapExport(
        tester,
        done: () => find.text('Deck saved').evaluate().isNotEmpty,
        reason: 'the save confirmation',
      );

      expect(find.text('Deck saved'), findsOneWidget);
      expect(shareCalls, isEmpty);
      await settleTimers(tester);
    });

    testWidgets('does nothing when the user cancels the save dialog', (
      tester,
    ) async {
      saveDialogAnswer = () async => null;

      // The dialog was asked, and the option is idle again — the cancel has
      // been handled, not just not yet reached.
      await tapExport(
        tester,
        done: () => saveDialogCalls == 1 && exportIdle(),
        reason: 'the cancelled save to be handled',
      );

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

      await tapExport(
        tester,
        done: () => shareCalls.isNotEmpty,
        reason: 'the share sheet fallback',
      );

      expect(shareCalls, hasLength(1));
      expect(find.byType(SnackBar), findsNothing);
      await settleTimers(tester);
    });
  });
}
