import 'dart:async';

import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/decks/deck_view_model.dart';
import 'package:discere/learning/decks/widgets/action_button.dart';
import 'package:discere/learning/decks/widgets/button_content.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/deck_stat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final loc = lookupAppLocalizations(const Locale('en'));

  Future<void> pumpButton(
    WidgetTester tester,
    Future<DeckStat> deckStatFuture, {
    VoidCallback? onTap,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ActionButton(
            deck: DeckViewModel(
              stored: BaseDeck(id: 'deck-1', name: 'Deck', description: ''),
              learnedCount: 30,
              totalCount: 150,
            ),
            onTap: onTap ?? () {},
            deckStatFuture: deckStatFuture,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  String label(WidgetTester tester) =>
      tester.widget<ButtonContent>(find.byType(ButtonContent)).label;

  bool isEnabled(WidgetTester tester) =>
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed !=
      null;

  testWidgets('while the stat loads, is enabled and names no action', (
    tester,
  ) async {
    await pumpButton(tester, Completer<DeckStat>().future);

    expect(label(tester), isEmpty);
    expect(find.text(loc.commonNoFlashcardsAvailable), findsNothing);
    expect(isEnabled(tester), isTrue);
  });

  testWidgets('keeps its height when the stat arrives', (tester) async {
    final stat = Completer<DeckStat>();
    await pumpButton(tester, stat.future);
    final pendingHeight = tester.getSize(find.byType(ElevatedButton)).height;

    stat.complete(DeckStat(150, 120, 12));
    await tester.pumpAndSettle();

    expect(label(tester), isNotEmpty);
    expect(tester.getSize(find.byType(ElevatedButton)).height, pendingHeight);
  });

  testWidgets('counts the due cards, singular for one', (tester) async {
    await pumpButton(tester, Future.value(DeckStat(150, 0, 12)));
    expect(label(tester), 'Review 12 cards');
    expect(isEnabled(tester), isTrue);

    await pumpButton(tester, Future.value(DeckStat(150, 0, 1)));
    expect(label(tester), 'Review 1 card');
  });

  testWidgets('names the review, not the new cards, while both wait', (
    tester,
  ) async {
    await pumpButton(tester, Future.value(DeckStat(150, 120, 12)));

    expect(label(tester), 'Review 12 cards');
  });

  testWidgets('offers new cards without a count once nothing is due', (
    tester,
  ) async {
    await pumpButton(tester, Future.value(DeckStat(150, 120, 0)));

    expect(label(tester), 'Learn new cards');
    expect(isEnabled(tester), isTrue);
  });

  testWidgets('is disabled while every card is taken up and none is due', (
    tester,
  ) async {
    await pumpButton(tester, Future.value(DeckStat(150, 0, 0)));

    expect(label(tester), 'Nothing due right now');
    expect(isEnabled(tester), isFalse);
  });

  testWidgets('is disabled for a deck without a card', (tester) async {
    await pumpButton(tester, Future.value(DeckStat(0, 0, 0)));

    expect(label(tester), loc.commonNoFlashcardsAvailable);
    expect(isEnabled(tester), isFalse);
  });

  testWidgets('starts the session on tap', (tester) async {
    var taps = 0;
    await pumpButton(
      tester,
      Future.value(DeckStat(150, 120, 0)),
      onTap: () => taps++,
    );

    await tester.tap(find.byType(ElevatedButton));

    expect(taps, 1);
  });
}
