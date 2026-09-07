/// The classification rows carry the page's only real branch: a row is
/// tappable when the reference DB knows the ancestor's id and type, and its
/// names become copyable instead when it does not — a tap would otherwise do
/// nothing. That logic was private to the page until it moved into its own
/// widget.
library;

import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/taxonomy_detail/taxonomy_classification_row_view_model.dart';
import 'package:discere/catalog/taxonomy_detail/widgets/taxonomy_classification_section.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

TaxonomyClassificationRowViewModel _row({
  String? id,
  SearchEntityType? entityType,
}) => TaxonomyClassificationRowViewModel(
  label: 'Familie',
  scientificName: 'Pomacentridae',
  commonName: 'Riffbarsche',
  id: id,
  entityType: entityType,
);

void main() {
  testWidgets('a row with an id and a type navigates on tap', (tester) async {
    final navigated = <SearchResult>[];
    await tester.pumpWidget(
      _buildApp(
        TaxonomyClassificationSection(
          rows: [_row(id: 'fam-1', entityType: SearchEntityType.family)],
          accent: Colors.blue,
          emptyLabel: 'leer',
          onNavigate: navigated.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);

    await tester.tap(find.text('Pomacentridae'));
    await tester.pumpAndSettle();

    expect(navigated, hasLength(1));
    expect(navigated.single.id, 'fam-1');
    expect(navigated.single.type, SearchEntityType.family);
  });

  testWidgets('a row without an id is not navigable', (tester) async {
    final navigated = <SearchResult>[];
    await tester.pumpWidget(
      _buildApp(
        TaxonomyClassificationSection(
          rows: [_row()],
          accent: Colors.blue,
          emptyLabel: 'leer',
          onNavigate: navigated.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);

    await tester.tap(find.text('Pomacentridae'));
    await tester.pumpAndSettle();

    expect(navigated, isEmpty);
  });

  testWidgets('an empty section shows the empty label', (tester) async {
    await tester.pumpWidget(
      _buildApp(
        TaxonomyClassificationSection(
          rows: const [],
          accent: Colors.blue,
          emptyLabel: 'Keine Einordnung bekannt',
          onNavigate: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Keine Einordnung bekannt'), findsOneWidget);
  });
}

Widget _buildApp(Widget child) {
  return MaterialApp(
    locale: const Locale('de'),
    theme: ThemeData(splashFactory: NoSplash.splashFactory),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}
