import 'package:discere/app/bootstrap/app_restart.dart';
import 'package:discere/app/settings/widgets/settings_reference_db_section.dart';
import 'package:discere/catalog/model/source.dart';
import 'package:discere/catalog/service/source_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/model/app_exception.dart';
import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:discere/shared/persistence/reference_db_update_service.dart';
import 'package:discere/shared/persistence/reference_db_update_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../mocks.mocks.dart';
import '../../../support/reference_db_updates.dart';

Source _source(String id, String name, String version) => Source(
  id: id,
  name: name,
  category: 'Database',
  citation: name,
  url: 'https://example.org/$id',
  licenseKey: 'CC BY-NC',
  version: version,
  displayOrder: 10,
);

void main() {
  var restarts = 0;
  late MockSourceRepository sources;

  setUp(() {
    restarts = 0;
    SharedPreferences.setMockInitialValues({
      ReferenceDatabaseProvisioner.prefKeyVersion: 2,
    });
    sources = MockSourceRepository();
    when(sources.findAll()).thenAnswer(
      (_) async => [
        _source('fishbase', 'FishBase', 'v26.07'),
        _source('sealifebase', 'SeaLifeBase', 'v26.04'),
      ],
    );
  });

  Future<void> pumpSection(
    WidgetTester tester,
    ReferenceDbUpdateService updates,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: updates),
          Provider.value(value: SourceService(sources)),
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
          home: const Scaffold(
            body: SingleChildScrollView(child: SettingsReferenceDbSection()),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows the installed version and its data releases', (
    tester,
  ) async {
    await pumpSection(
      tester,
      FixedReferenceDbUpdates(const ReferenceDbUpToDate()),
    );

    expect(find.text('Version 2'), findsOneWidget);
    expect(
      find.text('Datenstand: FishBase v26.07, SeaLifeBase v26.04'),
      findsOneWidget,
    );
    expect(find.text('Auf dem neuesten Stand.'), findsOneWidget);
  });

  testWidgets('leaves the data releases out when they cannot be read', (
    tester,
  ) async {
    when(sources.findAll()).thenThrow(StateError('no reference db'));

    await pumpSection(
      tester,
      FixedReferenceDbUpdates(const ReferenceDbUpToDate()),
    );

    expect(find.text('Version 2'), findsOneWidget);
    expect(find.textContaining('Datenstand'), findsNothing);
  });

  for (final (description, state) in [
    ('nothing was checked', const ReferenceDbUpdateNotChecked()),
    ('the installed one is the newest', const ReferenceDbUpToDate()),
    (
      'the check failed',
      ReferenceDbUpdateCheckFailed(NetworkException('offline')),
    ),
  ]) {
    testWidgets('checks by hand when $description', (tester) async {
      final updates = FixedReferenceDbUpdates(state);
      await pumpSection(tester, updates);

      await tester.tap(
        find.byKey(const Key('settings_reference_db_check_button')),
      );

      expect(updates.checkCalls, 1);
    });
  }

  testWidgets('says what a failed check ran into', (tester) async {
    await pumpSection(
      tester,
      FixedReferenceDbUpdates(
        ReferenceDbUpdateCheckFailed(NetworkException('offline')),
      ),
    );

    expect(
      find.text(
        'Die Suche nach Updates ist fehlgeschlagen. Keine Internetverbindung.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('offers no check while one runs', (tester) async {
    await pumpSection(
      tester,
      FixedReferenceDbUpdates(const ReferenceDbUpdateChecking()),
    );

    expect(find.text('Suche nach Updates…'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('downloads a declined update after the same confirmation as '
      'at start', (tester) async {
    final updates = FixedReferenceDbUpdates(
      ReferenceDbUpdateAvailable(referenceDbUpdateOf(3), declined: true),
    );
    await pumpSection(tester, updates);
    expect(find.text('Version 3 verfügbar (etwa 90 MB)'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('settings_reference_db_download_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jetzt aktualisieren'));
    await tester.pumpAndSettle();

    expect(updates.downloadCalls, 1);
  });

  testWidgets('follows a running download', (tester) async {
    await pumpSection(
      tester,
      FixedReferenceDbUpdates(
        ReferenceDbUpdateDownloading(referenceDbUpdateOf(3), progress: 0.444),
      ),
    );

    expect(
      find.text('Artendatenbank wird heruntergeladen – 40 von 90 MB'),
      findsOneWidget,
    );
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('tries a failed download again', (tester) async {
    final updates = FixedReferenceDbUpdates(
      ReferenceDbUpdateDownloadFailed(
        referenceDbUpdateOf(3),
        NetworkException('offline'),
      ),
    );
    await pumpSection(tester, updates);

    await tester.tap(
      find.byKey(const Key('settings_reference_db_retry_button')),
    );

    expect(updates.downloadCalls, 1);
  });

  testWidgets('applies a staged update, also with its notice put aside', (
    tester,
  ) async {
    await pumpSection(
      tester,
      FixedReferenceDbUpdates(
        const ReferenceDbUpdateStaged(3, noticeDismissed: true),
      ),
    );
    expect(
      find.text('Version 3 ist heruntergeladen. Anwenden startet die App neu.'),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('settings_reference_db_apply_button')),
    );

    expect(restarts, 1);
  });
}
