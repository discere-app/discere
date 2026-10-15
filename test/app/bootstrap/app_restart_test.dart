import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:discere/app/bootstrap/app_restart.dart';
import 'package:discere/app/bootstrap/app_session.dart';
import 'package:discere/app/flashcard_app.dart';
import 'package:discere/app/main_screen/main_screen_page.dart';
import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:discere/shared/persistence/staged_reference_db.dart';
import 'package:discere/shared/persistence/user_data_writes.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'bootstrap_harness.dart';

const _downloadUrl = 'https://example.org/discere_reference.db.gz';

/// What the update carries in its `metadata` table and the installed
/// fixture does not, to tell after the restart which file is open.
const _updateMarker = 'test_release';

/// Serves a manifest for reference-DB version 2 and, as its download, a copy
/// of the fixture marked with [_updateMarker]; every other request fails.
/// Run inside `tester.runAsync`.
Future<http.Client> _serverWithUpdate(Directory dir) async {
  final path = p.join(dir.path, 'update.db');
  await File(fixturePath).copy(path);
  final db = await databaseFactoryFfi.openDatabase(path);
  await db.insert('metadata', {'key': _updateMarker, 'value': 'version 2'});
  await db.execute('PRAGMA journal_mode = DELETE');
  await db.close();
  final compressed = gzip.encode(await File(path).readAsBytes());
  return MockClient((request) async {
    if (request.url.path.endsWith('manifest.json')) {
      return http.Response(
        jsonEncode({
          'version': 2,
          'schemaVersion': 2,
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

/// A session whose [stop] starts a write sequence and returns without
/// waiting for it, as stopping the background work can.
class _SessionWritingWhileStopping implements AppSession {
  _SessionWritingWhileStopping(this._write);

  final Future<void> Function() _write;

  @override
  final userDataWrites = UserDataWrites();

  /// The sequence [stop] started.
  late final Future<void> writeStartedByStop;

  @override
  Future<T> restartOnce<T>(Future<T> Function() restart) => restart();

  @override
  Future<void> stop() async {
    writeStartedByStop = userDataWrites.run(_write);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
    await pumpBootstrapApp(
      tester,
      network: await _serverWithUpdate(await supportDir.createTemp('server')),
    );
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

  testWidgets('the restart waits for a write sequence under way, so its '
      'second step still reaches the database', (tester) async {
    final outcome = await tester.runAsync(() async {
      await startAndConfirmUpdate(tester);
      await pumpUntil(tester, () => notice.evaluate().isNotEmpty);
      final app = find.byType(FlashcardApp);
      final writes = Provider.of<UserDataWrites>(
        tester.element(app),
        listen: false,
      );

      // Two steps on one connection, as a repository runs them, with the
      // second held back until the restart is already waiting.
      final firstStepDone = Completer<void>();
      final releaseSecondStep = Completer<void>();
      final sequence = writes.run(() async {
        final db = await DatabaseHelper.userDb;
        await db.insert('decks', {
          'id': 'first-step',
          'name': 'first',
          'description': '',
        });
        firstStepDone.complete();
        await releaseSecondStep.future;
        await db.insert('decks', {
          'id': 'second-step',
          'name': 'second',
          'description': '',
        });
      });
      await firstStepDone.future;

      await tester.tap(applyButton);
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final restartedWhileWriting = app.evaluate().isNotEmpty;

      releaseSecondStep.complete();
      final sequenceError = await sequence.then<Object?>(
        (_) => null,
        onError: (Object error) => error,
      );
      await pumpUntil(
        tester,
        () => app.evaluate().isNotEmpty,
        reason: 'the restarted app',
      );
      final decks = await (await DatabaseHelper.userDb).query('decks');
      return (
        restartedWhileWriting: restartedWhileWriting,
        sequenceError: sequenceError,
        deckIds: {for (final row in decks) row['id']},
      );
    });
    await tester.runAsync(() => stopApp(tester));

    expect(outcome!.restartedWhileWriting, isFalse);
    expect(outcome.sequenceError, isNull);
    expect(outcome.deckIds, containsAll(['first-step', 'second-step']));
  });

  testWidgets('the restart waits for a write sequence that starts while the '
      'session stops, before it closes the database', (tester) async {
    final outcome = await tester.runAsync(() async {
      await seedDatabases(supportDir);
      final db = await DatabaseHelper.userDb;
      var writeDone = false;
      final session = _SessionWritingWhileStopping(() async {
        // Held past the restart's own steps, on the connection it closes.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await db.insert('decks', {
          'id': 'written-while-stopping',
          'name': 'deck',
          'description': '',
        });
        writeDone = true;
      });

      var writeDoneWhenBootstrapRan = false;
      final restart = restartApp(session, () async {
        writeDoneWhenBootstrapRan = writeDone;
      });
      // The restart's first step waits for a frame.
      await tester.pump();
      final writeError = await session.writeStartedByStop.then<Object?>(
        (_) => null,
        onError: (Object error) => error,
      );
      await restart;
      final decks = await (await DatabaseHelper.userDb).query('decks');
      await DatabaseHelper.close();
      return (
        writeError: writeError,
        writeDoneWhenBootstrapRan: writeDoneWhenBootstrapRan,
        deckIds: {for (final row in decks) row['id']},
      );
    });

    expect(outcome!.writeError, isNull);
    expect(outcome.writeDoneWhenBootstrapRan, isTrue);
    expect(outcome.deckIds, contains('written-while-stopping'));
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
        openDatabaseMarker: (await (await DatabaseHelper.referenceDb).query(
          'metadata',
          where: 'key = ?',
          whereArgs: [_updateMarker],
        )).map((row) => row['value']).toList(),
        stillStaged: await StagedReferenceDb(
          await ReferenceDatabaseProvisioner.resolveLocalPath(),
        ).hasFile,
        pushedRouteShown: pushedRoute.evaluate().isNotEmpty,
        onHome: find.byType(MainScreenPage).evaluate().isNotEmpty,
        noticeShown: notice.evaluate().isNotEmpty,
      );
    });
    await tester.runAsync(() => stopApp(tester));

    expect(outcome!.noticeOverPushedRoute, isTrue);
    expect(outcome.installedBeforeApply, 1, reason: 'staged, not installed');
    expect(outcome.installedAfter, 2);
    expect(
      outcome.openDatabaseMarker,
      ['version 2'],
      reason: 'the restarted app reads the new file',
    );
    expect(outcome.stillStaged, isFalse);
    expect(outcome.pushedRouteShown, isFalse);
    expect(outcome.onHome, isTrue);
    expect(outcome.noticeShown, isFalse);
  });
}
