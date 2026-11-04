import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/decks/add_to_deck/add_to_deck_sheet.dart';
import 'package:discere/learning/decks/deck_view_model.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/deck_stat.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../../mocks.mocks.dart';
import '../../../support/persisted_warnings.dart';

void main() {
  final loc = lookupAppLocalizations(const Locale('en'));
  late MockDecksService decksService;

  setUp(() {
    decksService = MockDecksService();
  });

  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<DecksService>.value(
        value: decksService,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: AddToDeckSheet(speciesIds: {'s1'}, speciesNames: {'S one'}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a failed deck list load is logged and shows the error, not '
      '"no decks"', (tester) async {
    final warnings = recordPersistedWarnings();
    when(
      decksService.getAllDecks(),
    ).thenAnswer((_) => Future.error(StateError('list broken')));

    await pumpSheet(tester);

    expect(find.text(loc.errorWithDetail(loc.errorGeneric)), findsOneWidget);
    expect(find.text(loc.addToDeckSheetNoExistingDecks), findsNothing);
    expect(warnings.single, startsWith('[AddToDeckSheet] Deck list load'));
    expect(find.byKey(const Key('add_to_deck_create_new')), findsOneWidget);
  });

  testWidgets('an empty deck list says there are no decks', (tester) async {
    when(decksService.getAllDecks()).thenAnswer((_) async => <DeckViewModel>[]);

    await pumpSheet(tester);

    expect(find.text(loc.addToDeckSheetNoExistingDecks), findsOneWidget);
  });

  testWidgets('a failed add is reported in the sheet, which stays open and '
      'adds on a second try', (tester) async {
    final enrichmentQueue = MockINatEnrichmentQueueService();
    when(
      enrichmentQueue.scheduleDeckEnrichment(
        any,
        includeINatPhotos: anyNamed('includeINatPhotos'),
        includeCommonNames: anyNamed('includeCommonNames'),
      ),
    ).thenAnswer((_) async {});
    when(decksService.getAllDecks()).thenAnswer(
      (_) async => [
        DeckViewModel(
          stored: BaseDeck(id: 'd1', name: 'Reef', description: ''),
          stat: DeckStat(0, 0, 0),
        ),
      ],
    );
    var attempts = 0;
    when(decksService.addSpeciesToDeck('d1', {'s1'})).thenAnswer((_) async {
      if (attempts++ == 0) throw StateError('disk full');
    });
    bool? added;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<DecksService>.value(value: decksService),
          ChangeNotifierProvider<INatEnrichmentQueueService>.value(
            value: enrichmentQueue,
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => added = await showAddToDeckSheet(
                  context,
                  speciesIds: {'s1'},
                  speciesNames: {'S one'},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final target = find.byKey(const ValueKey('add_to_deck_target_d1'));

    await tester.tap(target);
    await tester.pumpAndSettle();

    expect(find.byType(AddToDeckSheet), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AddToDeckSheet),
        matching: find.text(loc.addToDeckFailed(loc.errorGeneric)),
      ),
      findsOneWidget,
    );
    expect(added, isNull);

    await tester.tap(target);
    await tester.pumpAndSettle();
    // The second tap reaches the deck: the sheet is no longer locked.
    verify(decksService.addSpeciesToDeck('d1', {'s1'})).called(2);
    await tester.tap(find.byKey(const Key('inat_skip_button')));
    await tester.pumpAndSettle();

    expect(find.byType(AddToDeckSheet), findsNothing);
    expect(added, isTrue);
  });
}
