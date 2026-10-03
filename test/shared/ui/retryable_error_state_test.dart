import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/ui/retryable_error_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpErrorState(
    WidgetTester tester, {
    required VoidCallback onRetry,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: RetryableErrorState(
            icon: Icons.error_outline,
            message: 'Could not load the deck: Something went wrong.',
            onRetry: onRetry,
            retryButtonKey: const Key('retry'),
          ),
        ),
      ),
    );
  }

  testWidgets('shows the icon, the error title and the message', (
    tester,
  ) async {
    await pumpErrorState(tester, onRetry: () {});

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.text('Error'), findsOneWidget);
    expect(
      find.text('Could not load the deck: Something went wrong.'),
      findsOneWidget,
    );
  });

  testWidgets('the retry button carries the given key and calls onRetry', (
    tester,
  ) async {
    var retries = 0;
    await pumpErrorState(tester, onRetry: () => retries++);

    expect(
      find.descendant(
        of: find.byKey(const Key('retry')),
        matching: find.text('Retry'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('retry')));

    expect(retries, 1);
  });
}
