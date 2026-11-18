import 'package:discere/app/bootstrap/app_restart.dart';
import 'package:discere/app/diagnostics/diagnostics_image_storage_sweep_request.dart';
import 'package:discere/enrichment/media/service/species_image_storage_sweeper.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/l10n/app_localizations_delegates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  var restarts = 0;

  setUp(() {
    restarts = 0;
    SharedPreferences.setMockInitialValues({});
  });

  /// Opens the confirmation and answers it with the button labelled
  /// [answer].
  Future<void> requestAndAnswer(WidgetTester tester, String answer) async {
    await tester.pumpWidget(
      Provider.value(
        value: AppRestart(() => restarts++),
        child: MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => requestImageStorageSweepOnRestart(context),
              child: const Text('request'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('request'));
    await tester.pumpAndSettle();
    expect(find.text('Bildspeicher aufräumen?'), findsOneWidget);
    await tester.tap(find.text(answer));
    await tester.pumpAndSettle();
  }

  Future<bool?> sweepRequested() async =>
      (await SharedPreferences.getInstance()).getBool(
        SpeciesImageStorageSweeper.prefKeySweepRequested,
      );

  testWidgets('once confirmed, asks the next start for a sweep and '
      'restarts', (tester) async {
    await requestAndAnswer(tester, 'Neu starten');

    expect(await sweepRequested(), isTrue);
    expect(restarts, 1);
  });

  testWidgets('cancelled, neither asks for a sweep nor restarts', (
    tester,
  ) async {
    await requestAndAnswer(tester, 'Abbrechen');

    expect(await sweepRequested(), isNull);
    expect(restarts, 0);
  });
}
