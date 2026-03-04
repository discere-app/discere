import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:discere/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  group('Create Deck Page', () {
    testWidgets('can navigate to Create Deck and see Cover Image options',
        (tester) async {
      await app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // 1. Open FAB
      final fab = find.byKey(const ValueKey('main-fab'));
      await tester.tap(fab);
      await tester.pumpAndSettle();

      // 2. Tap Create Deck
      final createButton = find.byIcon(Icons.create_new_folder_outlined);
      await tester.tap(createButton);
      await tester.pumpAndSettle();

      // 3. Verify labels on Create Deck Page
      expect(find.text('Create New Deck'), findsOneWidget);
      expect(find.text('Cover Image'), findsOneWidget);

      // 4. Verify Image Picker buttons
      expect(find.byIcon(Icons.photo_library), findsWidgets); // Gallery button
      expect(find.byIcon(Icons.search), findsWidgets);       // Search button

      // 5. Open Image Search Sheet
      final searchButton = find.descendant(
        of: find.byType(Scaffold),
        matching: find.byIcon(Icons.search),
      ).first;
      await tester.tap(searchButton);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));

      // 6. Verify Search Sheet is open
      expect(find.text('Search Wikimedia Commons'), findsWidgets);
      // TextField might be inside a layout widget that obscures it or has multiples
      expect(find.byType(TextField), findsWidgets);

      // Final cleanup
      await tester.pumpWidget(Container());
      await tester.pump(const Duration(milliseconds: 500));
    });
  });
}
