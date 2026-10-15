import 'package:discere/app/diagnostics/diagnostics_report_text.dart';
import 'package:discere/shared/persistence/reference_db_update_state.dart';
import 'package:discere/shared/persistence/reference_id/reference_id_migration_run.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/reference_db_updates.dart';
import 'diagnostics_page_data_fixture.dart';

void main() {
  final ranAt = DateTime.utc(2026, 10, 15, 9, 30);

  group('the reference ID lines', () {
    test('show the update, the applied version and a successful run with '
        'its targets', () {
      final text = buildDiagnosticsReportText(
        diagnosticsPageData(
          referenceDbUpdateState: ReferenceDbUpdateAvailable(
            referenceDbUpdateOf(8),
            declined: true,
          ),
          referenceIdsAppliedVersion: 7,
          lastReferenceIdMigrationRun: ReferenceIdMigrationSucceeded(
            referenceDbVersion: 7,
            ranAt: ranAt,
            referencedIdCount: 120,
            aliasCount: 3,
            targets: const {
              'flashcard_stats': (rewritten: 1, dropped: 1),
              'preference watchlist': (rewritten: 1, dropped: 0),
            },
          ),
        ),
      );

      expect(
        text,
        contains(
          'reference db update: available v8 declined\n'
          'reference ids applied: 7\n'
          'reference id last run: succeeded v7 at 2026-10-15T09:30:00.000Z '
          'referenced=120 aliased=3 rewritten=2 dropped=1\n'
          '- flashcard_stats: 1 rewritten, 1 dropped\n'
          '- preference watchlist: 1 rewritten, 0 dropped\n',
        ),
      );
    });

    test('show a failed run', () {
      final text = buildDiagnosticsReportText(
        diagnosticsPageData(
          referenceDbUpdateState: const ReferenceDbUpdateStaged(8),
          referenceIdsAppliedVersion: 6,
          lastReferenceIdMigrationRun: ReferenceIdMigrationFailed(
            referenceDbVersion: 7,
            ranAt: ranAt,
          ),
        ),
      );

      expect(text, contains('reference db update: staged v8\n'));
      expect(
        text,
        contains(
          'reference id last run: failed v7 at 2026-10-15T09:30:00.000Z\n',
        ),
      );
    });

    test('say when no run was recorded', () {
      final text = buildDiagnosticsReportText(diagnosticsPageData());

      expect(text, contains('reference ids applied: null\n'));
      expect(text, contains('reference id last run: none\n'));
    });
  });

  group('the reference db sources line', () {
    test('lists each source with its release', () {
      final text = buildDiagnosticsReportText(
        diagnosticsPageData(
          referenceDbSources: [
            referenceDbSource('fishbase', 'FishBase', version: 'v26.07'),
            referenceDbSource('sealifebase', 'SeaLifeBase', version: 'v26.04'),
          ],
        ),
      );

      expect(
        text,
        contains('reference db sources: fishbase=v26.07, sealifebase=v26.04\n'),
      );
    });

    test('says none when there are none', () {
      expect(
        buildDiagnosticsReportText(diagnosticsPageData()),
        contains('reference db sources: none\n'),
      );
    });
  });
}
