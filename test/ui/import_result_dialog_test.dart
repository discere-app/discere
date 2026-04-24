import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/import/import_result_dialog.dart';
import 'package:discere/learning/service/deck_import_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'renders unresolved names dialog without viewport layout assertions',
    (tester) async {
      await tester.pumpWidget(_buildApp());

      final dialogContext = tester.element(find.byType(Scaffold));
      final future = showImportResultDialog(
        dialogContext,
        DeckImportResult(
          importedDeckIds: const ['deck-1', 'deck-2', 'deck-3'],
          imageUrlByDeckId: const {},
          unresolvedNamesByDeckId: {
            'deck-1': List<String>.generate(25, (i) => 'Species $i'),
          },
          lastError: null,
          attemptedCount: 3,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Species 0'), findsOneWidget);
      expect(find.text('Species 24'), findsOneWidget);

      await tester.tap(find.byKey(const Key('import_result_close_button')));
      await tester.pumpAndSettle();

      expect(await future, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _buildApp() {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: const Scaffold(body: SizedBox.shrink()),
  );
}
