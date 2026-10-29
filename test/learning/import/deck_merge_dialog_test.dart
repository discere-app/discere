import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/import/deck_merge_dialog.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/model/create_subdeck.dart';
import 'package:discere/learning/repository/deck_merge_repository.dart';
import 'package:discere/learning/service/deck_merge_service.dart';
import 'package:discere/learning/service/favorite_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/learning_test_stack.dart';

const _greatWhite = 'Carcharodon carcharias';
const _whaleShark = 'Rhincodon typus';
const _hammerhead = 'Sphyrna lewini';

CreateDeck _deck(
  String sourceId,
  Set<String> names, {
  List<String>? supersedes,
  List<CreateSubdeck>? subdecks,
}) => CreateDeck(
  name: 'Deck $sourceId',
  description: '',
  sourceId: sourceId,
  speciesNames: names,
  supersedes: supersedes,
  subdecks: subdecks,
);

/// An entry joining two levels, with a subdeck for each level and one for a
/// species neither had — every species in a subdeck.
final _joined = _deck(
  'all',
  {_greatWhite, _whaleShark, _hammerhead},
  supersedes: ['level-1', 'level-2'],
  subdecks: [
    CreateSubdeck(id: 's1', name: 'One', speciesNames: {_greatWhite}),
    CreateSubdeck(id: 's2', name: 'Two', speciesNames: {_whaleShark}),
    CreateSubdeck(id: 's3', name: 'New', speciesNames: {_hammerhead}),
  ],
);

Finder _checkbox(String subdeckId) =>
    find.byKey(Key('deck_merge_subdeck_checkbox_$subdeckId'));

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
  Set<String>? confirmed;

  CheckboxListTile checkboxOf(WidgetTester tester, String subdeckId) =>
      tester.widget<CheckboxListTile>(_checkbox(subdeckId));

  /// Taps [subdeckId]'s checkbox, scrolled into view first.
  Future<void> toggle(WidgetTester tester, String subdeckId) async {
    await tester.ensureVisible(_checkbox(subdeckId));
    await tester.pumpAndSettle();
    await tester.tap(_checkbox(subdeckId));
    await tester.pumpAndSettle();
  }

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
      'lost, and resolves to null on cancel', (tester) async {
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
    expect(confirmed, isNull);
  });

  testWidgets('a deck another entry still takes species from stays, and '
      'confirming a target without subdecks resolves to no subdecks', (
    tester,
  ) async {
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
    expect(find.byType(CheckboxListTile), findsNothing);

    await tester.tap(find.byKey(const Key('deck_merge_confirm_button')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(confirmed, isEmpty);
  });

  testWidgets('offers the target\'s subdecks as suggested, and confirming '
      'resolves to the ones the user chose', (tester) async {
    final plan = await planFor(
      tester,
      [
        _deck('level-1', {_greatWhite}),
        _deck('level-2', {_whaleShark}),
      ],
      _joined,
      [_joined],
    );

    await showFor(tester, plan);

    expect(
      find.text(
        'Which subdecks do you want to learn? You can change this later '
        'when editing the deck.',
      ),
      findsOneWidget,
    );
    expect(find.text('One'), findsOneWidget);
    expect(find.text('1 species'), findsNWidgets(3));
    expect(checkboxOf(tester, 's1').value, isTrue);
    expect(checkboxOf(tester, 's2').value, isTrue);
    expect(checkboxOf(tester, 's3').value, isFalse);

    await toggle(tester, 's1');
    await toggle(tester, 's3');
    await tester.tap(find.byKey(const Key('deck_merge_confirm_button')));
    await tester.pumpAndSettle();

    expect(confirmed, {'s2', 's3'});
  });

  testWidgets('the last subdeck chosen cannot be unchecked while every '
      'species is in a subdeck', (tester) async {
    final entry = _deck(
      'all',
      {_greatWhite, _whaleShark},
      supersedes: ['level-1'],
      subdecks: _joined.subdecks!.take(2).toList(),
    );
    final plan = await planFor(
      tester,
      [
        _deck('level-1', {_greatWhite}),
      ],
      entry,
      [entry],
    );

    await showFor(tester, plan);
    expect(checkboxOf(tester, 's1').value, isTrue);
    expect(checkboxOf(tester, 's1').onChanged, isNull);

    await toggle(tester, 's2');
    expect(checkboxOf(tester, 's1').onChanged, isNotNull);
  });

  testWidgets('with many subdecks the dialog scrolls on a small screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final entry = _deck(
      'all',
      {_greatWhite},
      supersedes: ['level-1'],
      subdecks: [
        for (var i = 0; i < 12; i++)
          CreateSubdeck(
            id: 'p$i',
            name: 'Part $i',
            speciesNames: i == 0 ? {_greatWhite} : {'Unresolved name $i'},
          ),
      ],
    );
    final plan = await planFor(
      tester,
      [
        _deck('level-1', {_greatWhite, _whaleShark, _hammerhead}),
      ],
      entry,
      [entry],
    );

    await showFor(tester, plan);
    await toggle(tester, 'p11');

    expect(tester.takeException(), isNull);
    expect(checkboxOf(tester, 'p11').value, isTrue);
  });
}
