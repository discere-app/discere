import 'package:discere/catalog/search/search_empty_state.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('says that nothing was found', (tester) async {
    await tester.pumpWidget(_buildEmptyState());

    expect(find.text('No results found'), findsOneWidget);
  });

  testWidgets('offers the online search and reports the tap', (tester) async {
    var startedOnlineSearches = 0;
    await tester.pumpWidget(
      _buildEmptyState(
        showOnlineSearchAction: true,
        onSearchOnline: () => startedOnlineSearches++,
      ),
    );

    await tester.tap(find.text('Continue search online'));

    expect(startedOnlineSearches, 1);
  });

  testWidgets('leaves the online search out when it is not offered', (
    tester,
  ) async {
    await tester.pumpWidget(_buildEmptyState());

    expect(find.text('Continue search online'), findsNothing);
  });
}

Widget _buildEmptyState({
  bool showOnlineSearchAction = false,
  bool isSearchingOnline = false,
  VoidCallback? onSearchOnline,
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
      body: SearchEmptyState(
        showOnlineSearchAction: showOnlineSearchAction,
        isSearchingOnline: isSearchingOnline,
        onSearchOnline: onSearchOnline ?? () {},
      ),
    ),
  );
}
