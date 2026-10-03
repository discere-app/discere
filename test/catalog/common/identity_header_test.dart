import 'package:discere/catalog/common/taxon_identity/identity_header.dart';
import 'package:discere/catalog/common/taxon_identity/taxon_identity_view_model.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _buildApp(TaxonIdentityViewModel identity, {Widget? languageSelector}) {
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
      body: SingleChildScrollView(
        child: IdentityHeader(
          identity: identity,
          languageSelector: languageSelector,
        ),
      ),
    ),
  );
}

/// The "Species" pill, as opposed to the text inside it.
final _badge = find
    .ancestor(of: find.text('Species'), matching: find.byType(Container))
    .first;

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

  const identity = TaxonIdentityViewModel(
    primaryName: 'Weißer Hai',
    scientificName: 'Carcharodon carcharias',
    commonNames: ['Weißer Hai'],
    isEnglishFallback: false,
  );

  // The header's content starts this far in from its edge: its padding plus
  // the one-pixel border.
  const inset = AppSpacing.s20 + 1;

  testWidgets('leads the badge row with the language selector, in the '
      'header\'s top-left corner above the name', (tester) async {
    await tester.pumpWidget(
      _buildApp(identity, languageSelector: const Text('selector')),
    );

    final header = tester.getRect(find.byType(IdentityHeader));
    final selector = tester.getRect(find.text('selector'));
    final badge = tester.getRect(_badge);

    expect(selector.left, header.left + inset);
    expect(badge.left, selector.right + AppSpacing.s8);
    expect(badge.center.dy, moreOrLessEquals(selector.center.dy));
    expect(
      tester.getRect(find.text('Weißer Hai')).top,
      greaterThan(selector.bottom),
    );
  });

  testWidgets('starts the row with the badge when there is no selector', (
    tester,
  ) async {
    await tester.pumpWidget(_buildApp(identity));

    expect(
      tester.getRect(_badge).left,
      tester.getRect(find.byType(IdentityHeader)).left + inset,
    );
  });

  testWidgets('keeps selector and badge inside the header on a narrow '
      'screen, even when large text makes the badge wider than the row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 8;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      _buildApp(
        identity,
        languageSelector: const SizedBox(width: 48, height: 28),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(_badge).right,
      lessThanOrEqualTo(
        tester.getRect(find.byType(IdentityHeader)).right - inset,
      ),
    );
  });
}
