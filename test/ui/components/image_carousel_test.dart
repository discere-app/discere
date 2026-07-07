import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/ui/fullscreen_image_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:discere/shared/ui/image_carousel.dart';
import 'package:discere/shared/model/carousel_image.dart';

void main() {
  Widget buildTestableWidget(
    List<String> images, {
    bool enableFullscreenOnTap = true,
    bool enableFullscreenOnLongPress = false,
  }) {
    final pictures = images
        .map(
          (path) => CarouselImage(localPath: path, attributionText: ''),
        )
        .toList();

    return MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ImageCarousel(
          pictures: pictures,
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 300),
          enableFullscreenOnTap: enableFullscreenOnTap,
          enableFullscreenOnLongPress: enableFullscreenOnLongPress,
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

    testWidgets('shows exactly 7 dots if images > 7 (sliding window)', (
      WidgetTester tester,
    ) async {
      final manyImages = List.generate(20, (i) => '$i.jpg');
      await tester.pumpWidget(buildTestableWidget(manyImages));
      await tester.pumpAndSettle();

      final dots = find.byType(AnimatedContainer);
      expect(dots, findsNWidgets(7));
    });

    testWidgets('active dot has a different size', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestableWidget(['1.jpg', '2.jpg', '3.jpg']));
      await tester.pumpAndSettle();

      final containers = tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .toList();

      // Dot 0 is active (width 20)
      expect(containers[0].constraints?.minWidth, 20.0);
      expect(containers[1].constraints?.minWidth, 8.0);
    });
  });

  group('ImageCarousel fullscreen', () {
    testWidgets('tap opens FullscreenImageViewer when enabled', (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(['a.jpg'], enableFullscreenOnTap: true),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(GestureDetector).first);
      await tester.pumpAndSettle();

      expect(find.byType(FullscreenImageViewer), findsOneWidget);
    });

    testWidgets('tap does not open FullscreenImageViewer when disabled',
        (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(['a.jpg'], enableFullscreenOnTap: false),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(GestureDetector).first);
      await tester.pumpAndSettle();

      expect(find.byType(FullscreenImageViewer), findsNothing);
    });

    testWidgets('long press opens FullscreenImageViewer when enabled',
        (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(
          ['a.jpg'],
          enableFullscreenOnTap: false,
          enableFullscreenOnLongPress: true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.byType(GestureDetector).first);
      await tester.pumpAndSettle();

      expect(find.byType(FullscreenImageViewer), findsOneWidget);
    });
  });
}
