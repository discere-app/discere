import 'package:discere/catalog/common/taxon_identity/display_language_selector.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _buildApp({
  required Language language,
  required List<Language> selectableLanguages,
  required ValueChanged<Language> onSelected,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: DisplayLanguageSelector(
        language: language,
        selectableLanguages: selectableLanguages,
        onSelected: onSelected,
      ),
    ),
  );
}

void main() {
  testWidgets('shows the current language as an upper-case code', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildApp(
        language: Language.fr,
        selectableLanguages: const [Language.fr],
        onSelected: (_) {},
      ),
    );

    expect(find.text('FR'), findsOneWidget);
    expect(find.byTooltip('Switch language'), findsOneWidget);
  });

  testWidgets('lists exactly the selectable languages, by their name in the '
      'app language, and checks the current one', (tester) async {
    await tester.pumpWidget(
      _buildApp(
        language: Language.de,
        selectableLanguages: const [Language.de, Language.en],
        onSelected: (_) {},
      ),
    );

    await tester.tap(find.text('DE'));
    await tester.pumpAndSettle();

    expect(find.byType(PopupMenuItem<Language>), findsNWidgets(2));
    expect(
      find.descendant(
        of: find.widgetWithText(PopupMenuItem<Language>, 'German'),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(PopupMenuItem<Language>, 'English'),
        matching: find.byIcon(Icons.check),
      ),
      findsNothing,
    );
  });

  testWidgets('reports the picked language and leaves the displayed one to '
      'the caller', (tester) async {
    final selected = <Language>[];
    await tester.pumpWidget(
      _buildApp(
        language: Language.de,
        selectableLanguages: const [Language.de, Language.en],
        onSelected: selected.add,
      ),
    );

    await tester.tap(find.text('DE'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(selected, [Language.en]);
    expect(find.text('DE'), findsOneWidget);
  });
}
