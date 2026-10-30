import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/decks/deck_view_model.dart';
import 'package:discere/learning/decks/widgets/deck_progress_row.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpRow(
    WidgetTester tester, {
    required int learnedCount,
    required int totalCount,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: DeckProgressRow(
            deck: DeckViewModel(
              stored: BaseDeck(id: 'deck-1', name: 'Deck', description: ''),
              learnedCount: learnedCount,
              totalCount: totalCount,
            ),
          ),
        ),
      ),
    );
  }

  /// Every label and value the semantics tree announces.
  List<String> announced(WidgetTester tester) {
    final texts = <String>[];
    bool visit(SemanticsNode node) {
      final data = node.getSemanticsData();
      texts.addAll([data.label, data.value].where((text) => text.isNotEmpty));
      node.visitChildren(visit);
      return true;
    }

    final owner = tester.binding.renderViews.single.owner!;
    visit(owner.semanticsOwner!.rootSemanticsNode!);
    return texts;
  }

  testWidgets('shows the learned/total count beside the bar', (tester) async {
    await pumpRow(tester, learnedCount: 30, totalCount: 150);

    expect(find.text('30/150'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, 0.2);
  });

  testWidgets('shows no 0/0 for a deck without a card', (tester) async {
    await pumpRow(tester, learnedCount: 0, totalCount: 0);

    expect(find.text('0/0'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('is announced once, as one sentence', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpRow(tester, learnedCount: 30, totalCount: 150);

    expect(announced(tester), ['30 of 150 learned']);
    semantics.dispose();
  });

  testWidgets('announces nothing for a deck without a card', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpRow(tester, learnedCount: 0, totalCount: 0);

    expect(announced(tester), isEmpty);
    semantics.dispose();
  });
}
