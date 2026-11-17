import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/decks/deck_download_choice_dialog.dart';
import 'package:discere/learning/import/import_result_dialog.dart';
import 'package:discere/learning/service/deck_import_service.dart';
import 'package:discere/shared/l10n/app_localizations_delegates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

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

      await tester.tap(
        find.byKey(const Key('import_result_no_download_button')),
      );
      await tester.pumpAndSettle();

      expect(await future, DeckDownloadChoice.none);
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _buildApp() {
  return MaterialApp(
    theme: ThemeData(splashFactory: NoSplash.splashFactory),
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const Scaffold(body: SizedBox.shrink()),
  );
}
