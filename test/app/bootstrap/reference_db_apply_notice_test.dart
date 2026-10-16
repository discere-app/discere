import 'dart:async';
import 'dart:io';

import 'package:discere/app/bootstrap/app_restart.dart';
import 'package:discere/app/bootstrap/reference_db_apply_notice.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/model/app_exception.dart';
import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:discere/shared/persistence/reference_db_update_service.dart';
import 'package:discere/shared/persistence/reference_db_update_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/reference_db_updates.dart';

void main() {
  var restarts = 0;

  Future<void> pumpNotice(
    WidgetTester tester,
    ReferenceDbUpdateService updates,
  ) => tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: updates),
        Provider.value(value: AppRestart(() => restarts++)),
      ],
      child: MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => ReferenceDbApplyNotice(child: child!),
        home: const Scaffold(body: Text('route')),
      ),
    ),
  );

  setUp(() => restarts = 0);

  group('with a fixed state', () {
    testWidgets('shows nothing while no update is on its way', (tester) async {
      for (final state in [
        const ReferenceDbUpdateChecking(),
        const ReferenceDbUpToDate(),
        ReferenceDbUpdateAvailable(referenceDbUpdateOf(3), declined: true),
        const ReferenceDbUpdateStaged(3, noticeDismissed: true),
      ]) {
        await pumpNotice(tester, FixedReferenceDbUpdates(state));
        expect(find.byType(MaterialBanner), findsNothing, reason: '$state');
        expect(
          find.byKey(const Key('reference_db_download_notice')),
          findsNothing,
          reason: '$state',
        );
      }
    });

    testWidgets('shows the download in megabytes over a bar', (tester) async {
      await pumpNotice(
        tester,
        FixedReferenceDbUpdates(
          ReferenceDbUpdateDownloading(referenceDbUpdateOf(3), progress: 0.45),
        ),
      );

      expect(
        find.text('Artendatenbank wird heruntergeladen – 41 von 90 MB'),
        findsOneWidget,
      );
      final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const Key('reference_db_download_progress_bar')),
      );
      expect(bar.value, 0.45);
    });

    testWidgets('says it is preparing once every byte is in', (tester) async {
      await pumpNotice(
        tester,
        FixedReferenceDbUpdates(
          ReferenceDbUpdateDownloading(referenceDbUpdateOf(3), progress: 1),
        ),
      );

      expect(find.text('Artendatenbank wird vorbereitet…'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const Key('reference_db_download_progress_bar')),
      );
      expect(bar.value, isNull);
    });

    testWidgets('reports a failed download in words and tries again', (
      tester,
    ) async {
      final updates = FixedReferenceDbUpdates(
        ReferenceDbUpdateDownloadFailed(
          referenceDbUpdateOf(3),
          NetworkException('offline'),
        ),
      );
      await pumpNotice(tester, updates);

      expect(
        find.text(
          'Das Update der Artendatenbank konnte nicht heruntergeladen '
          'werden. Keine Internetverbindung.',
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('reference_db_download_retry_button')),
      );
      expect(updates.downloadCalls, 1);
    });

    testWidgets('offers to apply a staged update', (tester) async {
      await pumpNotice(
        tester,
        FixedReferenceDbUpdates(const ReferenceDbUpdateStaged(3)),
      );

      await tester.tap(
        find.byKey(const Key('reference_db_apply_notice_apply_button')),
      );
      expect(restarts, 1);
    });
  });

  group('following a real download', () {
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('apply_notice_test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, (call) async => tempDir.path);
      SharedPreferences.setMockInitialValues({
        ReferenceDatabaseProvisioner.prefKeyVersion: 2,
      });
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, null);
      await tempDir.delete(recursive: true);
    });

    testWidgets('shows the progress the downloader reports, then the update '
        'to apply', (tester) async {
      final downloader = FakeReferenceDbDownloader()
        ..progressSteps = const [0.1, 0.25, 0.444]
        ..release = Completer<void>();
      final updates = buildReferenceDbUpdates(downloader);
      await pumpNotice(tester, updates);

      final download = tester.runAsync(() async {
        await updates.checkAtStart();
        unawaited(updates.download());
        // Until the download waits for its release, past every report.
        while (downloader.downloads == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await download;
      await tester.pump();

      expect(
        find.text('Artendatenbank wird heruntergeladen – 40 von 90 MB'),
        findsOneWidget,
      );

      await tester.runAsync(() async {
        downloader.release!.complete();
        while (updates.state is! ReferenceDbUpdateStaged) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump();

      expect(
        find.byKey(const Key('reference_db_apply_notice')),
        findsOneWidget,
      );
    });
  });
}
