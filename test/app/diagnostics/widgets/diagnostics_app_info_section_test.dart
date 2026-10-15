import 'package:discere/app/diagnostics/diagnostics_page_data.dart';
import 'package:discere/app/diagnostics/widgets/diagnostics_app_info_section.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/persistence/reference_id/reference_id_migration_run.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../diagnostics_page_data_fixture.dart';

void main() {
  final ranAt = DateTime(2026, 10, 15, 9, 30);

  Future<void> pumpSection(WidgetTester tester, DiagnosticsPageData data) =>
      tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
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

  testWidgets('shows a staged update and a successful rewrite with its '
      'numbers', (tester) async {
    await pumpSection(
      tester,
      diagnosticsPageData(
        stagedReferenceDbVersion: 8,
        referenceIdsAppliedVersion: 7,
        lastReferenceIdMigrationRun: ReferenceIdMigrationSucceeded(
          referenceDbVersion: 7,
          ranAt: ranAt,
          referencedIdCount: 120,
          aliasCount: 3,
          targets: const {'flashcard_stats': (rewritten: 2, dropped: 1)},
        ),
      ),
    );

    expect(find.text('Staged, installed on restart: v8'), findsOneWidget);
    // The time is the locale's short date and time, as elsewhere on the
    // page; what matters here is the line around it.
    expect(
      find.textContaining(
        RegExp(
          r'^Applied for v7\nLast run .+ \(v7\): 2 rewritten, 1 dropped; '
          r'120 IDs checked, 3 of them aliased$',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows a failed rewrite without its error', (tester) async {
    await pumpSection(
      tester,
      diagnosticsPageData(
        availableReferenceDbVersion: 8,
        lastReferenceIdMigrationRun: ReferenceIdMigrationFailed(
          referenceDbVersion: 7,
          ranAt: ranAt,
        ),
      ),
    );

    expect(find.text('Available: v8'), findsOneWidget);
    expect(
      find.textContaining(
        RegExp(
          r'^Not applied for any version yet\.\n'
          r'Last run .+ \(v7\) failed, details in the log$',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('says when there is no update and no recorded run', (
    tester,
  ) async {
    await pumpSection(tester, diagnosticsPageData());

    expect(find.text('No update known.'), findsOneWidget);
    expect(
      find.text('Not applied for any version yet.\nNo run recorded.'),
      findsOneWidget,
    );
  });
}
