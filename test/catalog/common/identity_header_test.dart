import 'package:discere/catalog/common/taxon_identity/identity_header.dart';
import 'package:discere/catalog/common/taxon_identity/taxon_identity_view_model.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _buildApp(TaxonIdentityViewModel identity) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: IdentityHeader(identity: identity)),
  );
}

void main() {
  testWidgets('shows no hint icon when the primary name is not an English '
      'fallback', (tester) async {
    await tester.pumpWidget(
      _buildApp(
        const TaxonIdentityViewModel(
          primaryName: 'Weißer Hai',
          scientificName: 'Carcharodon carcharias',
          commonNames: ['Weißer Hai'],
          isEnglishFallback: false,
        ),
      ),
    );

    expect(find.byIcon(Icons.info_outline), findsNothing);
  });

  testWidgets(
    'shows a tap-to-explain hint icon when the primary name is an English '
    'fallback',
    (tester) async {
      await tester.pumpWidget(
        _buildApp(
          const TaxonIdentityViewModel(
            primaryName: 'Great white shark',
            scientificName: 'Carcharodon carcharias',
            commonNames: ['Great white shark'],
            isEnglishFallback: true,
          ),
        ),
      );

      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(find.text('About this name'), findsNothing);

      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();

      expect(find.text('About this name'), findsOneWidget);
      expect(
        find.text(
          'No name in your language is available for this species yet, '
          'so the English name is shown instead.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('About this name'), findsNothing);
    },
  );
}
