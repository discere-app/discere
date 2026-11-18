import 'package:discere/app/diagnostics/diagnostics_page_data.dart';
import 'package:discere/app/diagnostics/widgets/diagnostics_enrichment_section.dart';
import 'package:discere/enrichment/media/model/species_image_storage_sweep.dart';
import 'package:discere/enrichment/media/model/species_image_sweep_trigger.dart';
import 'package:discere/enrichment/model/enrichment_work_state.dart';
import 'package:discere/enrichment/pipeline/model/enrichment_work_state_count.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/l10n/app_localizations_delegates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../diagnostics_page_data_fixture.dart';

void main() {
  Future<void> pumpSection(
    WidgetTester tester,
    DiagnosticsPageData data, {
    VoidCallback? onSweepImageStorage,
  }) => tester.pumpWidget(
    MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: DiagnosticsEnrichmentSection(
            data: data,
            cooldown: null,
            onResetStuckJobs: () {},
            onCloseAllEnrichment: () {},
            onSweepImageStorage: onSweepImageStorage ?? () {},
          ),
        ),
      ),
    ),
  );

  testWidgets('the enrichment queue lists each state by its wire name', (
    tester,
  ) async {
    await pumpSection(
      tester,
      diagnosticsPageData(
        workStateCounts: const [
          EnrichmentWorkStateCount(
            label: 'base',
            state: EnrichmentWorkState.retryScheduled,
            count: 3,
          ),
          EnrichmentWorkStateCount(
            label: 'base',
            state: EnrichmentWorkState.done,
            count: 12,
          ),
        ],
      ),
    );

    expect(find.text('retryScheduled: 3'), findsOneWidget);
    expect(find.text('done: 12'), findsOneWidget);
  });

  group('the image storage', () {
    testWidgets('shows the last sweep with what it deleted per '
        'directory', (tester) async {
      await pumpSection(
        tester,
        diagnosticsPageData(
          lastImageStorageSweep: SpeciesImageStorageSweep(
            sweptAt: DateTime(2026, 11, 18, 9, 30),
            trigger: SpeciesImageSweepTrigger.manual,
            directories: const {
              'external_images': ImageDirectorySweep(
                deletedFiles: 12,
                freedBytes: 3 * 1024 * 1024,
              ),
              'reference_images': ImageDirectorySweep(
                deletedFiles: 4,
                freedBytes: 2048,
              ),
            },
            neededSpeciesCount: 140,
            releasedSpeciesCount: 9,
            duration: const Duration(milliseconds: 820),
          ),
        ),
      );

      expect(
        find.text(
          'Zuletzt am 18. Nov. 2026 09:30 (manuell, 820 ms):\n'
          '140 Arten benötigt, 9 verworfen\n'
          'external_images: 12 Dateien gelöscht, 3.0 MB freigegeben\n'
          'reference_images: 4 Dateien gelöscht, 2.0 KB freigegeben',
        ),
        findsOneWidget,
      );
    });

    testWidgets('says when it was not swept yet', (tester) async {
      await pumpSection(tester, diagnosticsPageData());

      expect(find.text('Noch nicht aufgeräumt.'), findsOneWidget);
    });

    testWidgets('offers the sweep on restart', (tester) async {
      var requested = 0;
      await pumpSection(
        tester,
        diagnosticsPageData(),
        onSweepImageStorage: () => requested++,
      );

      final action = find.text('Bildspeicher beim Neustart aufräumen');
      await tester.ensureVisible(action);
      await tester.tap(action);

      expect(requested, 1);
    });
  });
}
