import 'package:discere/catalog/comparison/comparison_page_opener.dart';
import 'package:discere/catalog/comparison/model/comparison_list.dart';
import 'package:discere/catalog/comparison/service/comparison_list_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'fake_comparison_list_repository.dart';

/// A service over [lists] whose first load has already run.
Future<ComparisonListService> loadedComparisonListService(
  WidgetTester tester, [
  List<ComparisonList> lists = const [],
]) async {
  final service = ComparisonListService(FakeComparisonListRepository(lists));
  await tester.pump();
  return service;
}

/// Opens comparisons whose species resolve to nothing — enough to see the
/// page open, with its list's name.
final testComparisonPageOpener = ComparisonPageOpener(
  resolveFromCache: (_) async => const [],
  resolveWithDownload: (_) async => const [],
  buildSpeciesDetailPage: (_) => const SizedBox.shrink(),
);

/// [home] in a localized app (English) that provides [service], a
/// [ComparisonPageOpener] and [providers].
Widget comparisonTestApp({
  required ComparisonListService service,
  required Widget home,
  List<SingleChildWidget> providers = const [],
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ComparisonListService>.value(value: service),
      Provider<ComparisonPageOpener>.value(value: testComparisonPageOpener),
      ...providers,
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  );
}
