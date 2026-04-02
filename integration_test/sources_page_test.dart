import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_utils.dart';

void main() {
  initializeIntegrationTest();

  setUp(() async {
    await resetTestState();
  });

  testWidgets('Sources page shows FishBase and SeaLifeBase', (tester) async {
    await tester.runAsync(() async {
      final mockNotificationService = createMockNotificationService();
      await startApp(tester, notificationService: mockNotificationService);
    });

    // Navigate to Settings
    final settingsNavItems = find.byIcon(Icons.settings);
    await tester.tap(settingsNavItems.last);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Tap on Data Sources
    final dataSourcesTile = find.byIcon(Icons.info_outline);
    expect(dataSourcesTile, findsOneWidget);
    await tester.tap(dataSourcesTile);
    await tester.pumpAndSettle();
    
    // Give FutureBuilder time to resolve
    await Future.delayed(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // Verify SourcesPage Hero Title using Key
    expect(find.byKey(const Key('sources_hero_title')), findsOneWidget);

    // Define scrollable 
    final scrollable = find.byType(Scrollable).last;

    // Look for FishBase Card
    await tester.scrollUntilVisible(
      find.byKey(const Key('source_card_fishbase')),
      100.0,
      scrollable: scrollable,
    );
    expect(find.byKey(const Key('source_card_fishbase')), findsWidgets);

    // Look for SeaLifeBase Card
    await tester.scrollUntilVisible(
      find.byKey(const Key('source_card_sealifebase')),
      100.0,
      scrollable: scrollable,
    );
    expect(find.textContaining('SeaLifeBase'), findsWidgets);
    expect(find.byKey(const Key('source_card_sealifebase')), findsWidgets);
  });
}
