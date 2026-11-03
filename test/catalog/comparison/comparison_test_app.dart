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

/// [home] in a localized app (English) that provides [service] and
/// [providers].
Widget comparisonTestApp({
  required ComparisonListService service,
  required Widget home,
  List<SingleChildWidget> providers = const [],
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ComparisonListService>.value(value: service),
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
