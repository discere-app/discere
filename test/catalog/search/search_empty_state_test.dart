import 'package:discere/catalog/search/search_empty_state.dart';
import 'package:discere/catalog/search/search_results_presenter.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers the three states the empty search screen can be in — the online
/// search is still ahead, is running, or is behind us without a result —
/// because the difference between them is the only feedback the user gets
/// during a network round that answers nothing.
void main() {
  testWidgets('says that nothing was found', (tester) async {
    await tester.pumpWidget(_buildEmptyState());

    expect(find.text('No results found'), findsOneWidget);
  });

  testWidgets('offers the online search and reports the tap', (tester) async {
    var startedOnlineSearches = 0;
    await tester.pumpWidget(
      _buildEmptyState(
        onlineSearch: OnlineSearchStage.offered,
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

  testWidgets('keeps the action on screen with a spinner while the online '
      'search runs', (tester) async {
    await tester.pumpWidget(
      _buildEmptyState(onlineSearch: OnlineSearchStage.running),
    );

    expect(find.text('Searching online…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No results found'), findsOneWidget);
  });

  testWidgets('refuses a second tap while the online search runs', (
    tester,
  ) async {
    var startedOnlineSearches = 0;
    await tester.pumpWidget(
      _buildEmptyState(
        onlineSearch: OnlineSearchStage.running,
        onSearchOnline: () => startedOnlineSearches++,
      ),
    );

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    await tester.tap(find.text('Searching online…'));

    expect(startedOnlineSearches, 0);
  });

  testWidgets('says that the online search came up empty too, and stops '
      'offering it', (tester) async {
    await tester.pumpWidget(
      _buildEmptyState(onlineSearch: OnlineSearchStage.finished),
    );

    expect(
      find.text('No results found – the online search came up empty too.'),
      findsOneWidget,
    );
    expect(find.text('Continue search online'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });
}

Widget _buildEmptyState({
  OnlineSearchStage onlineSearch = OnlineSearchStage.unavailable,
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
        onlineSearch: onlineSearch,
        onSearchOnline: onSearchOnline ?? () {},
      ),
    ),
  );
}
