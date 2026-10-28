import 'dart:async';

import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/import/deck_merge_flow.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/model/create_subdeck.dart';
import 'package:discere/learning/repository/deck_merge_repository.dart';
import 'package:discere/learning/service/deck_import_service.dart';
import 'package:discere/learning/service/deck_merge_service.dart';
import 'package:discere/learning/service/deck_update_service.dart';
import 'package:discere/learning/service/favorite_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../mocks.mocks.dart';
import '../../support/learning_test_stack.dart';

final _entry = CreateDeck(
  name: 'All levels',
  description: '',
  sourceId: 'all',
  speciesNames: {'Carcharodon carcharias'},
  supersedes: ['level-1'],
);

/// [_entry] with two subdecks, the second holding no species of level 1.
final _entryWithSubdecks = _entry.copyWith(
  speciesNames: {'Carcharodon carcharias', 'Rhincodon typus'},
  subdecks: [
    CreateSubdeck(
      id: 'one',
      name: 'One',
      speciesNames: {'Carcharodon carcharias'},
    ),
    CreateSubdeck(id: 'two', name: 'Two', speciesNames: {'Rhincodon typus'}),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockDeckMergeService mergeService;
  late DeckUpdateService updateService;

  /// A real plan for merging [entry] into a local `level-1` deck — the
  /// merge itself is what the test holds back.
  Future<DeckMergePlan> realPlan(
    WidgetTester tester, [
    CreateDeck? entry,
  ]) async =>
      (await tester.runAsync(() async {
        final stack = await LearningTestStack.open();
        addTearDown(() => tester.runAsync(stack.close));
        await stack.importService.importDecks([
          CreateDeck(
            name: 'Level 1',
            description: '',
            sourceId: 'level-1',
            speciesNames: {'Carcharodon carcharias'},
          ),
        ]);
        return DeckMergeService(
          stack.decksService,
          stack.importService,
          mergeRepository: DeckMergeRepository(database: stack.userDb),
          subdeckRepository: stack.subdecks,
          deckConfigRepository: stack.deckConfigs,
          favoriteService: FavoriteService(
            await SharedPreferences.getInstance(),
          ),
          userDataWrites: stack.writes,
        ).plan(entry ?? _entry, [entry ?? _entry]);
      }))!;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    mergeService = MockDeckMergeService();
    final deckRepository = MockDeckRepository();
    when(deckRepository.getAllDecks()).thenAnswer((_) async => []);
    updateService = DeckUpdateService(
      deckRepository,
      MockRemoteDeckService(),
      await SharedPreferences.getInstance(),
    );
  });

  /// Pumps a page and returns a context to start flows from — the way a
  /// second entry point would while the first flow's dialogs cover the
  /// screen.
  Future<BuildContext> pumpHost(WidgetTester tester) async {
    late BuildContext hostContext;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<DeckMergeService>.value(value: mergeService),
          ChangeNotifierProvider<DeckUpdateService>.value(value: updateService),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                hostContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    return hostContext;
  }

  Future<void> confirmIfAsked(WidgetTester tester) async {
    await tester.pump();
    final confirm = find.byKey(const Key('deck_merge_confirm_button'));
    if (confirm.evaluate().isNotEmpty) {
      await tester.tap(confirm);
      await tester.pump();
    }
  }

  testWidgets('a running merge shows its progress and a second start does '
      'nothing', (tester) async {
    final plan = await realPlan(tester);
    final merging =
        Completer<({String targetDeckId, DeckImportResult? importResult})>();
    when(mergeService.plan(any, any)).thenAnswer((_) async => plan);
    when(
      mergeService.merge(any, activeSubdeckIds: anyNamed('activeSubdeckIds')),
    ).thenAnswer((_) => merging.future);
    final host = await pumpHost(tester);

    final first = runDeckMergeFlow(host, entry: _entry, catalog: [_entry]);
    await confirmIfAsked(tester);
    expect(find.byKey(const Key('deck_merge_progress_dialog')), findsOneWidget);
    expect(find.text('Merging decks…'), findsOneWidget);

    final second = runDeckMergeFlow(host, entry: _entry, catalog: [_entry]);
    await confirmIfAsked(tester);
    verify(
      mergeService.merge(any, activeSubdeckIds: anyNamed('activeSubdeckIds')),
    ).called(1);
    verify(mergeService.plan(any, any)).called(1);

    merging.complete((targetDeckId: 'target', importResult: null));
    expect(await first, isTrue);
    expect(await second, isFalse);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('deck_merge_progress_dialog')), findsNothing);
  });

  testWidgets('the progress dialog goes when the merge fails', (tester) async {
    final plan = await realPlan(tester);
    when(mergeService.plan(any, any)).thenAnswer((_) async => plan);
    when(
      mergeService.merge(any, activeSubdeckIds: anyNamed('activeSubdeckIds')),
    ).thenAnswer((_) async => throw StateError('x'));
    final host = await pumpHost(tester);

    final flow = runDeckMergeFlow(host, entry: _entry, catalog: [_entry]);
    await confirmIfAsked(tester);

    expect(await flow, isFalse);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('deck_merge_progress_dialog')), findsNothing);
    expect(find.textContaining('Merging failed'), findsOneWidget);
  });

  testWidgets('the merge gets the subdecks chosen in the dialog', (
    tester,
  ) async {
    final plan = await realPlan(tester, _entryWithSubdecks);
    expect(plan.suggestedActiveSubdeckIds, {'one'});
    when(mergeService.plan(any, any)).thenAnswer((_) async => plan);
    when(
      mergeService.merge(any, activeSubdeckIds: anyNamed('activeSubdeckIds')),
    ).thenAnswer((_) async => (targetDeckId: 'target', importResult: null));
    final host = await pumpHost(tester);

    final flow = runDeckMergeFlow(
      host,
      entry: _entryWithSubdecks,
      catalog: [_entryWithSubdecks],
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('deck_merge_subdeck_checkbox_two')));
    await tester.pump();
    await confirmIfAsked(tester);

    expect(await flow, isTrue);
    verify(
      mergeService.merge(plan, activeSubdeckIds: {'one', 'two'}),
    ).called(1);
  });
}
