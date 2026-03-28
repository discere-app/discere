import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:discere/ui/components/image_carousel.dart';

void main() {
  Widget buildTestableWidget(List<String> images) {
    return MaterialApp(
      home: Scaffold(
        body: ImageCarousel(
          images: images,
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 300),
        ),
      ),
    );
  }

  group('ImageCarousel Indicators Test', () {
    testWidgets('shows all dots if images <= 7', (WidgetTester tester) async {
      final testImages = ['1.jpg', '2.jpg', '3.jpg'];
      await tester.pumpWidget(buildTestableWidget(testImages));
      await tester.pumpAndSettle();

      // Find all indicators (AnimatedContainer with BoxDecoration)
      final dots = find.byType(AnimatedContainer);
      expect(dots, findsNWidgets(testImages.length));
    });

    testWidgets('shows exactly 7 dots if images > 7 (sliding window)', (WidgetTester tester) async {
      final manyImages = List.generate(20, (i) => '$i.jpg');
      await tester.pumpWidget(buildTestableWidget(manyImages));
      await tester.pumpAndSettle();

      final dots = find.byType(AnimatedContainer);
      expect(dots, findsNWidgets(7));
    });

    testWidgets('active dot has a different size', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestableWidget(['1.jpg', '2.jpg', '3.jpg']));
      await tester.pumpAndSettle();

      final containers = tester.widgetList<AnimatedContainer>(find.byType(AnimatedContainer)).toList();
      
      // Dot 0 is active (width 20)
      expect(containers[0].constraints?.minWidth, 20.0);
      expect(containers[1].constraints?.minWidth, 8.0);
    });
  });
}
