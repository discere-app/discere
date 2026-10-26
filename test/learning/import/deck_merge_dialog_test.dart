import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/import/deck_merge_dialog.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/repository/deck_merge_repository.dart';
import 'package:discere/learning/service/deck_merge_service.dart';
import 'package:discere/learning/service/favorite_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/learning_test_stack.dart';

CreateDeck _deck(
  String sourceId,
  Set<String> names, {
  List<String>? supersedes,
}) => CreateDeck(
  name: 'Deck $sourceId',
  description: '',
  sourceId: sourceId,
  speciesNames: names,
  supersedes: supersedes,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The plan for merging [entry] out of [catalog] into the local [decks],
  /// worked out against real databases.
  Future<DeckMergePlan> planFor(
    WidgetTester tester,
    List<CreateDeck> decks,
    CreateDeck entry,
    List<CreateDeck> catalog,
  ) async => (await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues({});
    final stack = await LearningTestStack.open();
    addTearDown(() => tester.runAsync(stack.close));
    await stack.importService.importDecks(decks);
    final service = DeckMergeService(
      stack.decksService,
      stack.importService,
      mergeRepository: DeckMergeRepository(database: stack.userDb),
      subdeckRepository: stack.subdecks,
      deckConfigRepository: stack.deckConfigs,
      favoriteService: FavoriteService(await SharedPreferences.getInstance()),
      userDataWrites: stack.writes,
    );
    return service.plan(entry, catalog);
  }))!;

  /// What the dialog resolved to, once closed.
  bool? confirmed;

  Future<void> showFor(WidgetTester tester, DeckMergePlan plan) async {
    confirmed = null;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                confirmed = await showDeckMergeDialog(context, plan),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('names the decks that go and the species whose progress is '
      'lost, and resolves to false on cancel', (tester) async {
    final joined = _deck(
      'all',
      {'Carcharodon carcharias'},
      supersedes: ['level-1', 'level-2'],
    );
    final plan = await planFor(
      tester,
      [
        _deck('level-1', {'Carcharodon carcharias'}),
        _deck('level-2', {'Rhincodon typus', 'Prionace glauca'}),
      ],
      joined,
      [joined],
    );

    await showFor(tester, plan);

    expect(
      find.text('“Deck all” takes over your progress from these decks:'),
      findsOneWidget,
    );
    expect(
      find.text('Afterwards, Deck level-1, Deck level-2 are removed.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'The new deck does not contain 2 species; their progress is lost:',
      ),
      findsOneWidget,
    );
    expect(find.text('Prionace glauca'), findsOneWidget);
    expect(find.text('Rhincodon typus'), findsOneWidget);

    await tester.tap(find.byKey(const Key('deck_merge_cancel_button')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(confirmed, isFalse);
  });

  testWidgets('a deck another entry still takes species from stays, and '
      'confirming resolves to true', (tester) async {
    final sharks = _deck(
      'sharks',
      {'Carcharodon carcharias'},
      supersedes: ['old'],
    );
    final fish = _deck('fish', {'Amphiprion ocellaris'}, supersedes: ['old']);
    final plan = await planFor(
      tester,
      [
        _deck('old', {'Carcharodon carcharias', 'Amphiprion ocellaris'}),
      ],
      sharks,
      [sharks, fish],
    );

    await showFor(tester, plan);

    expect(find.textContaining('Deck old stays for now'), findsOneWidget);
    expect(find.textContaining('is removed'), findsNothing);
    expect(find.textContaining('progress is lost'), findsNothing);

    await tester.tap(find.byKey(const Key('deck_merge_confirm_button')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(confirmed, isTrue);
  });
}
