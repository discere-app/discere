import 'package:discere/learning/decks/widgets/deck_status_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _longText =
    'Updated 10 hours ago · names may have changed, and a little more';

void main() {
  group('DeckStatusLine', () {
    testWidgets('wraps a text too long for one line instead of cutting it', (
      tester,
    ) async {
      await tester.pumpWidget(_buildLine(width: 200));

      final paragraph = _paragraphOf(tester, _longText);
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(_lineCountOf(paragraph), greaterThan(1));
    });

    testWidgets('aligns both icons with the first line of a wrapped text', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildLine(
          width: 200,
          trailing: const Icon(Icons.info_outline, size: 12),
        ),
      );

      final paragraph = _paragraphOf(tester, _longText);
      expect(
        _lineCountOf(paragraph),
        greaterThan(1),
        reason: 'the alignment only shows once the text spans several lines',
      );

      final textTop = tester.getTopLeft(find.text(_longText)).dy;

      expect(tester.getTopLeft(find.byIcon(Icons.check)).dy, textTop);
      expect(tester.getTopLeft(find.byIcon(Icons.info_outline)).dy, textTop);
    });
  });
}

Widget _buildLine({required double width, Widget? trailing}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: DeckStatusLine(
            icon: Icons.check,
            text: _longText,
            color: Colors.green,
            trailing: trailing,
          ),
        ),
      ),
    ),
  );
}

RenderParagraph _paragraphOf(WidgetTester tester, String text) {
  return tester.renderObject<RenderParagraph>(
    find.descendant(of: find.text(text), matching: find.byType(RichText)),
  );
}

int _lineCountOf(RenderParagraph paragraph) {
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(
      baseOffset: 0,
      extentOffset: paragraph.text.toPlainText().length,
    ),
  );
  return boxes.map((box) => box.top).toSet().length;
}
