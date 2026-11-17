import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_utils.dart';

const _openSheet = Key('open_sheet');
const _sheetButton = Key('sheet_button');
const _sheetButtonResult = 'Sheet button tapped';

/// A page whose only button opens a modal bottom sheet, which slides in with
/// the stock entrance animation and holds a button that opens a dialog.
Widget _sheetApp() => MaterialApp(
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: ElevatedButton(
          key: _openSheet,
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            builder: (sheetContext) => Center(
              child: ElevatedButton(
                key: _sheetButton,
                onPressed: () => showDialog<void>(
                  context: sheetContext,
                  builder: (_) =>
                      const AlertDialog(content: Text(_sheetButtonResult)),
                ),
                child: const Text('Sheet button'),
              ),
            ),
          ),
          child: const Text('Open sheet'),
        ),
      ),
    ),
  ),
);

void main() {
  group('tapWhenHitTestable', () {
    testWidgets('taps a button in a bottom sheet that is still sliding in', (
      tester,
    ) async {
      await tester.pumpWidget(_sheetApp());

      await tester.tap(find.byKey(_openSheet));
      await tapWhenHitTestable(tester, find.byKey(_sheetButton));
      await tester.pumpAndSettle();

      expect(find.text(_sheetButtonResult), findsOneWidget);
    });

    testWidgets(
      'fails naming what it waited for when the widget stays covered',
      (tester) async {
        const covered = Key('covered');
        await tester.pumpWidget(
          MaterialApp(
            home: Stack(
              children: [
                Center(
                  child: ElevatedButton(
                    key: covered,
                    onPressed: () {},
                    child: const Text('Covered'),
                  ),
                ),
                const Positioned.fill(child: ColoredBox(color: Colors.black)),
              ],
            ),
          ),
        );

        // Caught by hand: `expectLater` is itself a guarded test API, and
        // flutter_test refuses to start it while the helper is still pumping.
        TestFailure? failure;
        try {
          await tapWhenHitTestable(
            tester,
            find.byKey(covered),
            description: 'the covered button',
            timeout: const Duration(seconds: 1),
          );
        } on TestFailure catch (caught) {
          failure = caught;
        }

        expect(failure?.message, contains('waiting for: the covered button'));
      },
    );
  });
}
