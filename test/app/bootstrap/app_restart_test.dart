import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:discere/app/flashcard_app.dart';
import 'package:discere/app/main_screen/main_screen_page.dart';
import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:discere/shared/persistence/staged_reference_db.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bootstrap_harness.dart';

const _downloadUrl = 'https://example.org/discere_reference.db.gz';

/// Serves a manifest for reference-DB version 2 and, as its download, the
/// fixture itself; every other request fails.
http.Client _serverWithUpdate() {
  final compressed = gzip.encode(File(fixturePath).readAsBytesSync());
  return MockClient((request) async {
    if (request.url.path.endsWith('manifest.json')) {
      return http.Response(
        jsonEncode({
          'version': 2,
          'schemaVersion': ReferenceDatabaseProvisioner.supportedSchemaVersion,
          'url': _downloadUrl,
          'sha256': sha256.convert(compressed).toString(),
          'compressedSizeBytes': compressed.length,
        }),
        200,
      );
    }
    if (request.url.toString() == _downloadUrl) {
      return http.Response.bytes(compressed, 200);
    }
    return http.Response('unavailable', 503);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  const nativeSplash = MethodChannel('flutter_native_splash');
  late Directory supportDir;

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp('app_restart_test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(pathProvider, (call) async {
      return supportDir.path;
    });
    messenger.setMockMethodCallHandler(nativeSplash, (call) async => null);
  });

  tearDown(() async {
    Logger.configurePersistence(enabled: false);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(pathProvider, null);
    messenger.setMockMethodCallHandler(nativeSplash, null);
    await supportDir.delete(recursive: true);
  });

  /// Starts the app at reference-DB version 1 with version 2 on the server,
  /// and confirms the update dialog the background check brings up. The
  /// download is staged from then on. Run inside `tester.runAsync`.
  Future<void> startAndConfirmUpdate(WidgetTester tester) async {
    await seedDatabases(supportDir);
    SharedPreferences.setMockInitialValues(installedPreferences());
    await pumpBootstrapApp(tester, network: _serverWithUpdate());
    final app = find.byType(FlashcardApp);
    await pumpUntil(tester, () => app.evaluate().isNotEmpty);
    final confirm = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(FilledButton),
    );
    await pumpUntil(tester, () => confirm.evaluate().isNotEmpty);
    await tester.tap(confirm);
  }

  final notice = find.byKey(const Key('reference_db_apply_notice'));
  final applyButton = find.byKey(
    const Key('reference_db_apply_notice_apply_button'),
  );

  testWidgets('"Apply" is disabled while a dialog is open, and enabled again '
      'once it is closed', (tester) async {
    final (withDialog, afterDialog) = await tester.runAsync(() async {
      await startAndConfirmUpdate(tester);
      await pumpUntil(tester, () => notice.evaluate().isNotEmpty);
      bool applyEnabled() =>
          tester.widget<FilledButton>(applyButton).onPressed != null;

      final dialogContext = tester.element(find.byType(MainScreenPage));
      showDialog<void>(
        context: dialogContext,
        builder: (_) => const AlertDialog(content: Text('busy')),
      ).ignore();
      await pumpUntil(tester, () => find.text('busy').evaluate().isNotEmpty);
      await tester.pump();
      final withDialog = applyEnabled();

      Navigator.of(dialogContext).pop();
      await pumpUntil(tester, () => find.text('busy').evaluate().isEmpty);
      await tester.pump();
      return (withDialog, applyEnabled());
    }) ?? (null, null);
    await tester.runAsync(DatabaseHelper.close);

    expect(withDialog, isFalse);
    expect(afterDialog, isTrue);
  });

  testWidgets('applying a staged update from a pushed route restarts the app '
      'onto the home screen, with the update installed and every service '
      'built anew', (tester) async {
    final outcome = await tester.runAsync(() async {
      await startAndConfirmUpdate(tester);
      final app = find.byType(FlashcardApp);

      Navigator.of(tester.element(find.byType(MainScreenPage))).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('pushed route')),
        ),
      ).ignore();
      final pushedRoute = find.text('pushed route');
      await pumpUntil(tester, () => pushedRoute.evaluate().isNotEmpty);
      await pumpUntil(tester, () => notice.evaluate().isNotEmpty);
      final noticeOverPushedRoute =
          pushedRoute.evaluate().isNotEmpty && notice.evaluate().isNotEmpty;
      final watchlistBefore = Provider.of<WatchlistService>(
        tester.element(app),
        listen: false,
      );
      final installedBeforeApply = (await SharedPreferences.getInstance())
          .getInt(ReferenceDatabaseProvisioner.prefKeyVersion);

      await tester.tap(applyButton);
      await pumpUntil(
        tester,
        () =>
            app.evaluate().isNotEmpty &&
            !identical(
              Provider.of<WatchlistService>(
                tester.element(app),
                listen: false,
              ),
              watchlistBefore,
            ),
        reason: 'the restarted app',
      );
      await tester.pump();
      return (
        noticeOverPushedRoute: noticeOverPushedRoute,
        installedBeforeApply: installedBeforeApply,
        installedAfter: (await SharedPreferences.getInstance()).getInt(
          ReferenceDatabaseProvisioner.prefKeyVersion,
        ),
        stillStaged: await StagedReferenceDb(
          await ReferenceDatabaseProvisioner.resolveLocalPath(),
        ).hasFile,
        pushedRouteShown: pushedRoute.evaluate().isNotEmpty,
        onHome: find.byType(MainScreenPage).evaluate().isNotEmpty,
        noticeShown: notice.evaluate().isNotEmpty,
      );
    });
    await tester.runAsync(DatabaseHelper.close);

    expect(outcome!.noticeOverPushedRoute, isTrue);
    expect(outcome.installedBeforeApply, 1, reason: 'staged, not installed');
    expect(outcome.installedAfter, 2);
    expect(outcome.stillStaged, isFalse);
    expect(outcome.pushedRouteShown, isFalse);
    expect(outcome.onHome, isTrue);
    expect(outcome.noticeShown, isFalse);
  });
}
