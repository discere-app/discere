import 'package:discere/app/diagnostics/widgets/diagnostics_enrichment_section.dart';
import 'package:discere/enrichment/model/enrichment_work_state.dart';
import 'package:discere/enrichment/pipeline/model/enrichment_work_state_count.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../diagnostics_page_data_fixture.dart';

void main() {
  testWidgets('the enrichment queue lists each state by its wire name', (
    tester,
  ) async {
    await tester.pumpWidget(
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
            child: DiagnosticsEnrichmentSection(
              data: diagnosticsPageData(
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
              cooldown: null,
              onResetStuckJobs: () {},
              onCloseAllEnrichment: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('retryScheduled: 3'), findsOneWidget);
    expect(find.text('done: 12'), findsOneWidget);
  });
}
