import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/ui/fullscreen_image_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// 1x1 transparent PNG
final _kTransparentPng = Uint8List.fromList([
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  0x00,
  0x00,
  0x00,
  0x0d,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1f,
  0x15,
  0xc4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0a,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9c,
  0x62,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0d,
  0x0a,
  0x2d,
  0xb4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4e,
  0x44,
  0xae,
  0x42,
  0x60,
  0x82,
]);

FullscreenImage _img({String attribution = ''}) => FullscreenImage(
  provider: MemoryImage(_kTransparentPng),
  attributionText: attribution,
);

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

void main() {
  group('FullscreenImageViewer', () {
    testWidgets('renders close button', (tester) async {
      await tester.pumpWidget(_wrap(FullscreenImageViewer(images: [_img()])));
      await tester.pump();
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('close button pops the route', (tester) async {
      bool popped = false;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                await FullscreenImageViewer.open(context, images: [_img()]);
                popped = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.close), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(popped, isTrue);
    });

    testWidgets('shows no page counter for single image', (tester) async {
      await tester.pumpWidget(_wrap(FullscreenImageViewer(images: [_img()])));
      await tester.pump();
      expect(find.textContaining('/ 1'), findsNothing);
    });

    testWidgets('shows page counter for multiple images', (tester) async {
      await tester.pumpWidget(
        _wrap(FullscreenImageViewer(images: [_img(), _img(), _img()])),
      );
      await tester.pump();
      expect(find.text('1 / 3'), findsOneWidget);
    });

    testWidgets('shows attribution text', (tester) async {
      await tester.pumpWidget(
        _wrap(
          FullscreenImageViewer(images: [_img(attribution: '© Test Author')]),
        ),
      );
      await tester.pump();
      expect(find.text('© Test Author'), findsOneWidget);
    });

    testWidgets('respects initialIndex', (tester) async {
      await tester.pumpWidget(
        _wrap(
          FullscreenImageViewer(
            images: [_img(), _img(), _img()],
            initialIndex: 1,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('2 / 3'), findsOneWidget);
    });

    group('orientation restore on close', () {
      Future<List<MethodCall>> pumpAndCollectOrientationCalls(
        WidgetTester tester, {
        List<DeviceOrientation>? restoreOrientations,
      }) async {
        final calls = <MethodCall>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            calls.add(call);
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => FullscreenImageViewer.open(
                  context,
                  images: [_img()],
                  restoreOrientations:
                      restoreOrientations ??
                      const [
                        DeviceOrientation.portraitUp,
                        DeviceOrientation.portraitDown,
                      ],
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        // Only orientation calls made after closing are relevant — opening
        // also issues one (to lift the lock), which isn't under test here.
        calls.clear();

        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        return calls
            .where((c) => c.method == 'SystemChrome.setPreferredOrientations')
            .toList();
      }

      testWidgets('defaults to restoring the portrait-only lock', (
        tester,
      ) async {
        final orientationCalls = await pumpAndCollectOrientationCalls(tester);

        expect(orientationCalls, hasLength(1));
        expect(orientationCalls.single.arguments, [
          'DeviceOrientation.portraitUp',
          'DeviceOrientation.portraitDown',
        ]);
      });

      testWidgets(
        'restores the caller-supplied orientations instead of forcing '
        'portrait, so a still-open unlocked screen underneath is not '
        're-locked',
        (tester) async {
          final orientationCalls = await pumpAndCollectOrientationCalls(
            tester,
            restoreOrientations: DeviceOrientation.values,
          );

          expect(orientationCalls, hasLength(1));
          expect(
            orientationCalls.single.arguments,
            DeviceOrientation.values.map((o) => o.toString()).toList(),
          );
        },
      );
    });
  });
}
