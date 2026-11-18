import 'package:discere/theme/ocean_theme/ocean_theme.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Every text style a [TextTheme] holds, keyed by its role name — read from
/// its diagnostics so that a role Flutter adds later is covered too.
Map<String, TextStyle?> _rolesOf(TextTheme textTheme) {
  final builder = DiagnosticPropertiesBuilder();
  textTheme.debugFillProperties(builder);
  return {
    for (final property in builder.properties)
      if (property is DiagnosticsProperty<TextStyle>)
        property.name!: property.value,
  };
}

/// The font family [text] is actually laid out with — read from the render
/// object, since a component style that replaces the theme's text style
/// instead of merging with it only shows up there.
String? _renderedFontFamily(WidgetTester tester, String text) {
  return tester
      .renderObject<RenderParagraph>(find.text(text))
      .text
      .style!
      .fontFamily;
}

void main() {
  _testFontThroughout('oceanTheme', oceanTheme, 'Lexend');
}

/// Every text of an app styled by [theme] is set in [fontFamily]: each role of
/// its text themes and each component that brings a text style of its own.
void _testFontThroughout(String themeName, ThemeData theme, String fontFamily) {
  Widget app(Widget home) => MaterialApp(theme: theme, home: home);

  group('$themeName text theme roles', () {
    for (final (name, textTheme) in [
      ('textTheme', theme.textTheme),
      ('primaryTextTheme', theme.primaryTextTheme),
    ]) {
      test('every role of $name is set in its font', () {
        final roles = _rolesOf(textTheme);

        expect(roles, hasLength(greaterThanOrEqualTo(15)));
        for (final MapEntry(key: role, value: style) in roles.entries) {
          expect(style?.fontFamily, fontFamily, reason: role);
        }
      });
    }
  });

  group('$themeName components render their text in its font', () {
    testWidgets('app bar title', (tester) async {
      await tester.pumpWidget(
        app(Scaffold(appBar: AppBar(title: const Text('Title')))),
      );

      expect(_renderedFontFamily(tester, 'Title'), fontFamily);
    });

    testWidgets('buttons', (tester) async {
      await tester.pumpWidget(
        app(
          Scaffold(
            body: Column(
              children: [
                ElevatedButton(onPressed: () {}, child: const Text('Elevated')),
                FilledButton(onPressed: () {}, child: const Text('Filled')),
                TextButton(onPressed: () {}, child: const Text('Text')),
                OutlinedButton(onPressed: () {}, child: const Text('Outlined')),
              ],
            ),
          ),
        ),
      );

      for (final label in ['Elevated', 'Filled', 'Text', 'Outlined']) {
        expect(_renderedFontFamily(tester, label), fontFamily, reason: label);
      }
    });

    testWidgets('bottom navigation labels', (tester) async {
      await tester.pumpWidget(
        app(
          Scaffold(
            bottomNavigationBar: BottomNavigationBar(
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home),
                  label: 'Selected',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.search),
                  label: 'Unselected',
                ),
              ],
            ),
          ),
        ),
      );

      expect(_renderedFontFamily(tester, 'Selected'), fontFamily);
      expect(_renderedFontFamily(tester, 'Unselected'), fontFamily);
    });

    testWidgets('input label and hint', (tester) async {
      // Separate fields: next to a resting label, the hint is not shown.
      await tester.pumpWidget(
        app(
          const Scaffold(
            body: Column(
              children: [
                TextField(decoration: InputDecoration(labelText: 'Label')),
                TextField(decoration: InputDecoration(hintText: 'Hint')),
              ],
            ),
          ),
        ),
      );

      expect(_renderedFontFamily(tester, 'Label'), fontFamily);
      expect(_renderedFontFamily(tester, 'Hint'), fontFamily);
    });

    testWidgets('snack bar and dialog', (tester) async {
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Snack')));
                  showDialog<void>(
                    context: context,
                    builder: (_) => const AlertDialog(
                      title: Text('Dialog title'),
                      content: Text('Dialog content'),
                    ),
                  );
                },
                child: const Text('show'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('show'));
      await tester.pumpAndSettle();

      for (final text in ['Snack', 'Dialog title', 'Dialog content']) {
        expect(_renderedFontFamily(tester, text), fontFamily, reason: text);
      }
    });
  });
}
