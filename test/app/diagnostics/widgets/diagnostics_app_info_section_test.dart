import 'package:discere/app/diagnostics/diagnostics_page_data.dart';
import 'package:discere/app/diagnostics/widgets/diagnostics_app_info_section.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/persistence/reference_db_update_check.dart';
import 'package:discere/shared/persistence/reference_id/reference_id_migration_run.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../diagnostics_page_data_fixture.dart';

void main() {
  final ranAt = DateTime(2026, 10, 15, 10, 12);

  Future<void> pumpSection(WidgetTester tester, DiagnosticsPageData data) =>
      tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: DiagnosticsAppInfoSection(data: data),
            ),
          ),
        ),
      );

  /// The subtitle of the tile titled [title].
  String subtitleOf(WidgetTester tester, String title) {
    final tile = tester.widget<ListTile>(
      find.ancestor(of: find.text(title), matching: find.byType(ListTile)),
    );
    return (tile.subtitle! as Text).data!;
  }

  group('the reference database', () {
    testWidgets('shows version, download date, size, data releases and '
        'format, without the schemas the app supports', (tester) async {
      await pumpSection(
        tester,
        diagnosticsPageData(
          referenceDbFileModifiedAt: DateTime(2026, 8, 21, 14),
          referenceDbSources: [
            referenceDbSource('fishbase', 'FishBase', version: 'v26.07'),
            referenceDbSource('sealifebase', 'SeaLifeBase', version: 'v26.04'),
          ],
        ),
      );

      expect(
        subtitleOf(tester, 'Referenzdatenbank'),
        'Version 7 · heruntergeladen am 21. Aug. 2026 · 86.0 MB\n'
        'Datenstand: FishBase v26.07, SeaLifeBase v26.04\n'
        'Format: Schema 2',
      );
    });

    testWidgets('leaves out the data releases it could not read', (
      tester,
    ) async {
      await pumpSection(tester, diagnosticsPageData());

      expect(
        subtitleOf(tester, 'Referenzdatenbank'),
        'Version 7 · 86.0 MB\nFormat: Schema 2',
      );
    });
  });

  group('the update', () {
    Future<String> updateLine(
      WidgetTester tester, {
      ReferenceDbUpdateCheck check = const ReferenceDbUpToDate(),
      int? staged,
    }) async {
      await pumpSection(
        tester,
        diagnosticsPageData(
          referenceDbUpdateCheck: check,
          stagedReferenceDbVersion: staged,
        ),
      );
      return subtitleOf(tester, 'Update der Referenzdatenbank');
    }

    testWidgets('names a staged one', (tester) async {
      expect(
        await updateLine(
          tester,
          check: const ReferenceDbNewerVersionFound(8),
          staged: 8,
        ),
        'Version 8 bereitgelegt – wird beim Neustart installiert',
      );
    });

    testWidgets('names an available one', (tester) async {
      expect(
        await updateLine(tester, check: const ReferenceDbNewerVersionFound(8)),
        'Version 8 verfügbar',
      );
    });

    testWidgets('still names one the user declined', (tester) async {
      expect(
        await updateLine(
          tester,
          check: const ReferenceDbNewerVersionFound(8, declined: true),
        ),
        'Version 8 verfügbar – für diese Sitzung abgelehnt',
      );
    });

    testWidgets('says when the installed one is the newest', (tester) async {
      expect(await updateLine(tester), 'Auf dem neuesten Stand.');
    });

    testWidgets('says when the check is still running', (tester) async {
      expect(
        await updateLine(tester, check: const ReferenceDbUpdateCheckRunning()),
        'Die Suche nach Updates läuft noch.',
      );
    });

    testWidgets('says when the check failed', (tester) async {
      expect(
        await updateLine(tester, check: const ReferenceDbUpdateCheckFailed()),
        'Die Suche nach Updates ist fehlgeschlagen – Details im Protokoll.',
      );
    });
  });

  group('the adjustment of learning progress', () {
    testWidgets('shows a successful run alone when it is the applied '
        'version', (tester) async {
      await pumpSection(
        tester,
        diagnosticsPageData(
          referenceIdsAppliedVersion: 7,
          lastReferenceIdMigrationRun: ReferenceIdMigrationSucceeded(
            referenceDbVersion: 7,
            ranAt: ranAt,
            referencedIdCount: 180,
            aliasCount: 160,
            targets: const {'flashcard_stats': (rewritten: 412, dropped: 0)},
          ),
        ),
      );

      expect(
        subtitleOf(tester, 'Anpassung der Lernstände'),
        'Zuletzt am 15. Okt. 2026 10:12 für Version 7:\n'
        '412 Einträge angepasst, 0 verworfen '
        '(180 IDs geprüft, 160 mit neuer ID)',
      );
    });

    testWidgets('adds the applied version to a failed run, without its '
        'error', (tester) async {
      await pumpSection(
        tester,
        diagnosticsPageData(
          referenceIdsAppliedVersion: 6,
          lastReferenceIdMigrationRun: ReferenceIdMigrationFailed(
            referenceDbVersion: 7,
            ranAt: ranAt,
          ),
        ),
      );

      expect(
        subtitleOf(tester, 'Anpassung der Lernstände'),
        'Zuletzt am 15. Okt. 2026 10:12 für Version 7 fehlgeschlagen – '
        'Details im Protokoll.\n'
        'Lernstände sind auf Version 6 angepasst.',
      );
    });

    testWidgets('shows only the applied version when no run was recorded', (
      tester,
    ) async {
      await pumpSection(
        tester,
        diagnosticsPageData(referenceIdsAppliedVersion: 7),
      );

      expect(
        subtitleOf(tester, 'Anpassung der Lernstände'),
        'Lernstände sind auf Version 7 angepasst.',
      );
    });

    testWidgets('says when it has not run yet', (tester) async {
      await pumpSection(tester, diagnosticsPageData());

      expect(
        subtitleOf(tester, 'Anpassung der Lernstände'),
        'Noch nicht gelaufen.',
      );
    });
  });
}
