import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoLocalizations;
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/l10n/app_localizations_delegates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The Material and Cupertino texts the framework draws itself — tooltips,
/// dialog buttons, pickers, the text selection menu — follow the app's
/// language, which takes the material_ui/cupertino_ui delegates: the widgets
/// look up their own localizations types, not the SDK's.
void main() {
  Future<BuildContext> pumpApp(WidgetTester tester, Locale locale) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox();
          },
        ),
      ),
    );
    return captured;
  }

  testWidgets('provides German Material texts', (tester) async {
    final context = await pumpApp(tester, const Locale('de'));

    expect(MaterialLocalizations.of(context).cancelButtonLabel, 'Abbrechen');
  });

  testWidgets('provides German Cupertino texts', (tester) async {
    final context = await pumpApp(tester, const Locale('de'));

    expect(CupertinoLocalizations.of(context).cutButtonLabel, 'Ausschneiden');
  });

  testWidgets('provides the app texts', (tester) async {
    final context = await pumpApp(tester, const Locale('de'));

    expect(AppLocalizations.of(context)?.tutorialSkip, 'Überspringen');
  });
}
