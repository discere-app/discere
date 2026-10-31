import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/enrichment/media/service/species_media_service.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/decks/edit/edit_deck_page.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/model/subdeck.dart';
import 'package:discere/learning/model/subdeck_edit.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/persistence/user_data_writes.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:discere/shared/service/user_preferences_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../mocks.mocks.dart';
import 'edit_deck_manual_enrichment_test.dart'
    show TestINatEnrichmentQueueService;

/// Covers the subdeck switches on EditDeckPage: part of the draft, saved
/// with the deck, and never leaving the deck without a card.

Species _species(String id) => Species(
  id,
  'Genus $id',
  'fishbase',
  id,
  const {},
  Classification(
    'Genus',
    const {},
    null,
    'Family',
    const {},
    'Order',
    const {},
    'Class',
    const {},
    null,
  ),
  const [],
);

Subdeck _subdeck(String id, int sortOrder, {bool isActive = true}) => Subdeck(
  deckId: 'deck-1',
  id: id,
  name: 'Level $id',
  sortOrder: sortOrder,
  isActive: isActive,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockDecksService decksService;
  late MockFlashcardService flashcardService;
  late MockNotificationService notificationService;

  setUp(() {
    decksService = MockDecksService();
    flashcardService = MockFlashcardService();
    notificationService = MockNotificationService();
    when(
      notificationService.shouldPromptForPermission(),
    ).thenAnswer((_) async => false);
    when(
      flashcardService.getDeckConfig(any),
    ).thenAnswer((_) async => const DeckConfig(deckId: 'deck-1'));
    when(decksService.getSubdecks('deck-1')).thenAnswer(
      (_) async => [_subdeck('1', 0), _subdeck('2', 1, isActive: false)],
    );
  });

  /// [speciesIds] in the deck, each in the subdeck [subdeckBySpecies] says.
  Future<UserPreferencesService> pumpPage(
    WidgetTester tester, {
    required List<String> speciesIds,
    required Map<String, String> subdeckBySpecies,
    bool hasSeenSubdeckTutorial = true,
  }) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    when(
      decksService.getSpeciesByDeckId('deck-1'),
    ).thenAnswer((_) async => [for (final id in speciesIds) _species(id)]);
    when(
      decksService.getSubdeckIdBySpeciesId('deck-1'),
    ).thenAnswer((_) async => subdeckBySpecies);
    SharedPreferences.setMockInitialValues({
      'has_seen_edit_deck_tutorial': true,
      'has_seen_edit_deck_subdecks_tutorial': hasSeenSubdeckTutorial,
    });
    final prefs = UserPreferencesService(await SharedPreferences.getInstance());

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<DecksService>.value(value: decksService),
          Provider<ImageService>.value(value: MockImageService()),
          Provider<NotificationService>.value(value: notificationService),
          Provider<FlashcardService>.value(value: flashcardService),
          Provider<UserDataWrites>.value(value: UserDataWrites()),
          Provider<SpeciesMediaService>.value(value: MockSpeciesMediaService()),
          ChangeNotifierProvider<INatEnrichmentQueueService>.value(
            value: TestINatEnrichmentQueueService(),
          ),
          ChangeNotifierProvider<UserPreferencesService>.value(value: prefs),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: EditDeckPage(
            deck: BaseDeck(
              id: 'deck-1',
              name: 'Test Deck',
              description: 'Description',
              language: Language.en,
            ),
            buildSpeciesDetailPage: (speciesId, language) =>
                const SizedBox.shrink(),
          ),
        ),
      ),
    );
    if (hasSeenSubdeckTutorial) await tester.pumpAndSettle();
    return prefs;
  }

  SwitchListTile switchOf(WidgetTester tester, String subdeckId) =>
      tester.widget<SwitchListTile>(
        find.byKey(Key('edit_deck_subdeck_switch_$subdeckId')),
      );

  bool saveEnabled(WidgetTester tester) =>
      tester
          .widget<TextButton>(find.byKey(const Key('edit_deck_save_button')))
          .onPressed !=
      null;

  testWidgets('shows each subdeck with its species and saves a switch with '
      'the deck', (tester) async {
    when(
      decksService.updateDeck(
        any,
        addedSpeciesIds: anyNamed('addedSpeciesIds'),
        removedSpeciesIds: anyNamed('removedSpeciesIds'),
      ),
    ).thenAnswer((_) async {});
    await pumpPage(
      tester,
      speciesIds: ['a', 'b', 'c', 'free'],
      subdeckBySpecies: {'a': '1', 'b': '2', 'c': '2'},
    );

    expect(find.text('Level 1'), findsOneWidget);
    expect(find.text('1 species'), findsOneWidget);
    expect(find.text('2 species'), findsOneWidget);
    expect(switchOf(tester, '1').value, isTrue);
    expect(switchOf(tester, '2').value, isFalse);
    expect(saveEnabled(tester), isFalse);

    await tester.tap(find.byKey(const Key('edit_deck_subdeck_switch_2')));
    await tester.pumpAndSettle();
    expect(saveEnabled(tester), isTrue);

    await tester.tap(find.byKey(const Key('edit_deck_save_button')));
    await tester.pumpAndSettle();
    verify(decksService.setActiveSubdecks('deck-1', {'1', '2'})).called(1);
  });

  testWidgets('switching a subdeck back undoes the change', (tester) async {
    await pumpPage(
      tester,
      speciesIds: ['a', 'b'],
      subdeckBySpecies: {'a': '1', 'b': '2'},
    );

    await tester.tap(find.byKey(const Key('edit_deck_subdeck_switch_2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_deck_subdeck_switch_2')));
    await tester.pumpAndSettle();

    expect(saveEnabled(tester), isFalse);
  });

  testWidgets('the last subdeck on cannot be switched off while every '
      'species is in a subdeck', (tester) async {
    await pumpPage(
      tester,
      speciesIds: ['a', 'b'],
      subdeckBySpecies: {'a': '1', 'b': '2'},
    );

    expect(switchOf(tester, '1').onChanged, isNull);
    expect(switchOf(tester, '2').onChanged, isNotNull);
  });

  testWidgets('with a species outside the subdecks, the last one can be '
      'switched off', (tester) async {
    await pumpPage(
      tester,
      speciesIds: ['a', 'b', 'free'],
      subdeckBySpecies: {'a': '1', 'b': '2'},
    );

    expect(switchOf(tester, '1').onChanged, isNotNull);
  });

  testWidgets('removing the last species outside the subdecks while all are '
      'off switches them all on again', (tester) async {
    await pumpPage(
      tester,
      speciesIds: ['a', 'free'],
      subdeckBySpecies: {'a': '1'},
    );
    await tester.tap(find.byKey(const Key('edit_deck_subdeck_switch_1')));
    await tester.pumpAndSettle();
    expect(switchOf(tester, '1').value, isFalse);

    // The species list is sorted by name: 'Genus a' before 'Genus free'.
    await tester.tap(find.byTooltip('Remove').last);
    await tester.pumpAndSettle();

    expect(switchOf(tester, '1').value, isTrue);
    expect(switchOf(tester, '2').value, isTrue);
  });

  testWidgets('a deck without subdecks shows the section and saves none', (
    tester,
  ) async {
    when(decksService.getSubdecks('deck-1')).thenAnswer((_) async => []);
    await pumpPage(tester, speciesIds: ['a'], subdeckBySpecies: {});

    expect(find.text('Subdecks'), findsOneWidget);
    expect(
      find.byKey(const Key('edit_deck_subdeck_add_button')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('edit_deck_name_field')),
      'Renamed',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_deck_save_button')));
    await tester.pumpAndSettle();

    verifyNever(decksService.setActiveSubdecks(any, any));
    verifyNever(decksService.editSubdecks(any, any));
  });

  Future<void> openMenu(WidgetTester tester, String subdeckId) async {
    await tester.tap(find.byKey(Key('edit_deck_subdeck_menu_$subdeckId')));
    await tester.pumpAndSettle();
  }

  Future<void> chooseFromMenu(
    WidgetTester tester,
    String subdeckId,
    String item,
  ) async {
    await openMenu(tester, subdeckId);
    await tester.tap(find.byKey(Key('edit_deck_subdeck_menu_$item')));
    await tester.pumpAndSettle();
  }

  Future<void> enterName(WidgetTester tester, String name) async {
    await tester.enterText(
      find.byKey(const Key('edit_deck_subdeck_name_field')),
      name,
    );
    await tester.pumpAndSettle();
  }

  Future<void> confirmName(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const Key('edit_deck_subdeck_name_confirm_button')),
    );
    await tester.pumpAndSettle();
  }

  Future<void> addSubdeck(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(const Key('edit_deck_subdeck_add_button')));
    await tester.pumpAndSettle();
    await enterName(tester, name);
    await confirmName(tester);
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('edit_deck_save_button')));
    await tester.pumpAndSettle();
  }

  SubdeckEdit savedEdit() =>
      verify(decksService.editSubdecks('deck-1', captureAny)).captured.single
          as SubdeckEdit;

  group('editing the division', () {
    testWidgets('a new subdeck is on, shows up, makes the deck dirty and is '
        'saved before its switch, after deck and config', (tester) async {
      await pumpPage(
        tester,
        speciesIds: ['a'],
        subdeckBySpecies: {'a': '1'},
      );

      await addSubdeck(tester, 'Mine');

      expect(find.text('Mine'), findsOneWidget);
      expect(saveEnabled(tester), isTrue);
      await save(tester);

      final captured = verifyInOrder([
        decksService.updateDeck(
          any,
          addedSpeciesIds: anyNamed('addedSpeciesIds'),
          removedSpeciesIds: anyNamed('removedSpeciesIds'),
        ),
        flashcardService.saveDeckConfig(any),
        decksService.editSubdecks('deck-1', captureAny),
        decksService.setActiveSubdecks('deck-1', captureAny),
      ]).captured;
      final edit = captured[2].single as SubdeckEdit;
      final newId = edit.subdecks.last.id;
      expect(edit.subdecks.map((s) => s.name), [
        'Level 1',
        'Level 2',
        'Mine',
      ]);
      expect(edit.moves, isEmpty);
      expect(captured[3].single, {'1', newId});
    });

    testWidgets('an empty or taken name cannot be confirmed', (tester) async {
      await pumpPage(
        tester,
        speciesIds: ['a'],
        subdeckBySpecies: {'a': '1'},
      );
      await tester.tap(find.byKey(const Key('edit_deck_subdeck_add_button')));
      await tester.pumpAndSettle();
      bool canConfirm() =>
          tester
              .widget<TextButton>(
                find.byKey(const Key('edit_deck_subdeck_name_confirm_button')),
              )
              .onPressed !=
          null;

      expect(canConfirm(), isFalse);
      await enterName(tester, '   ');
      expect(canConfirm(), isFalse);
      await enterName(tester, ' level 1 ');
      expect(canConfirm(), isFalse);
      expect(
        find.text('There already is a subdeck with this name.'),
        findsOneWidget,
      );
      await enterName(tester, 'Level 3');
      expect(canConfirm(), isTrue);
    });

    testWidgets('renaming is saved, and renaming back undoes it', (
      tester,
    ) async {
      await pumpPage(
        tester,
        speciesIds: ['a'],
        subdeckBySpecies: {'a': '1'},
      );

      await chooseFromMenu(tester, '1', 'rename');
      await enterName(tester, 'First');
      await confirmName(tester);
      expect(find.text('First'), findsOneWidget);
      expect(saveEnabled(tester), isTrue);

      await chooseFromMenu(tester, '1', 'rename');
      await enterName(tester, 'Level 1');
      await confirmName(tester);
      expect(saveEnabled(tester), isFalse);

      await chooseFromMenu(tester, '1', 'rename');
      await enterName(tester, 'First');
      await confirmName(tester);
      await save(tester);
      expect(savedEdit().subdecks.first, (id: '1', name: 'First'));
    });

    testWidgets('deleting asks nothing, leaves the species in the deck and in '
        'no subdeck', (tester) async {
      await pumpPage(
        tester,
        speciesIds: ['a', 'b'],
        subdeckBySpecies: {'a': '1', 'b': '2'},
      );
      await chooseFromMenu(tester, '2', 'delete');

      expect(find.text('Level 2'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byTooltip('Remove'), findsNWidgets(2));
      await save(tester);

      final edit = savedEdit();
      expect(edit.subdecks, [(id: '1', name: 'Level 1')]);
      expect(edit.moves, {'b': null});
      verifyNever(
        decksService.updateDeck(
          any,
          addedSpeciesIds: anyNamed('addedSpeciesIds'),
          removedSpeciesIds: argThat(isNotEmpty, named: 'removedSpeciesIds'),
        ),
      );
    });

    testWidgets('dragging a handle reorders, and dragging back undoes it', (
      tester,
    ) async {
      await pumpPage(
        tester,
        speciesIds: ['a'],
        subdeckBySpecies: {'a': '1'},
      );
      Future<void> dragHandle(String subdeckId, double dy) async {
        final gesture = await tester.startGesture(
          tester.getCenter(
            find.byKey(Key('edit_deck_subdeck_drag_handle_$subdeckId')),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        for (var step = 0; step < 4; step++) {
          await gesture.moveBy(Offset(0, dy / 4));
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
        await gesture.up();
        await tester.pumpAndSettle();
      }

      final rowHeight =
          tester
              .getCenter(find.byKey(const Key('edit_deck_subdeck_switch_2')))
              .dy -
          tester
              .getCenter(find.byKey(const Key('edit_deck_subdeck_switch_1')))
              .dy;

      await dragHandle('1', rowHeight * 1.2);
      expect(
        tester.getCenter(find.text('Level 2')).dy,
        lessThan(tester.getCenter(find.text('Level 1')).dy),
      );
      expect(saveEnabled(tester), isTrue);

      await dragHandle('1', -rowHeight * 1.2);
      expect(saveEnabled(tester), isFalse);

      await dragHandle('1', rowHeight * 1.2);
      await save(tester);
      expect(savedEdit().subdecks.map((s) => s.id), ['2', '1']);
    });

    testWidgets('assigning moves the checked species into the subdeck on '
        'confirming, and back undoes nothing', (tester) async {
      await pumpPage(
        tester,
        speciesIds: ['a', 'b', 'free'],
        subdeckBySpecies: {'a': '1', 'b': '2'},
      );

      await chooseFromMenu(tester, '1', 'assign_species');
      await tester.tap(
        find.byKey(const Key('edit_deck_subdeck_species_tile_free')),
      );
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(saveEnabled(tester), isFalse);

      await chooseFromMenu(tester, '1', 'assign_species');
      await tester.tap(
        find.byKey(const Key('edit_deck_subdeck_species_tile_free')),
      );
      await tester.tap(
        find.byKey(const Key('edit_deck_subdeck_species_tile_a')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('edit_deck_subdeck_species_confirm_button')),
      );
      await tester.pumpAndSettle();

      expect(saveEnabled(tester), isTrue);
      await save(tester);
      expect(savedEdit().moves, {'free': '1', 'a': null});
    });

    testWidgets('a switch alone saves no edit', (tester) async {
      await pumpPage(
        tester,
        speciesIds: ['a', 'b'],
        subdeckBySpecies: {'a': '1', 'b': '2'},
      );

      await tester.tap(find.byKey(const Key('edit_deck_subdeck_switch_2')));
      await tester.pumpAndSettle();
      await save(tester);

      verify(decksService.setActiveSubdecks('deck-1', {'1', '2'})).called(1);
      verifyNever(decksService.editSubdecks(any, any));
    });

    testWidgets('removing a species saves no edit', (tester) async {
      await pumpPage(
        tester,
        speciesIds: ['a', 'b'],
        subdeckBySpecies: {'a': '1', 'b': '1'},
      );

      await tester.tap(find.byTooltip('Remove').last);
      await tester.pumpAndSettle();
      await save(tester);

      verifyNever(decksService.editSubdecks(any, any));
    });

    testWidgets('moving the last cards into a subdeck that is off switches '
        'all on', (tester) async {
      await pumpPage(
        tester,
        speciesIds: ['a'],
        subdeckBySpecies: {'a': '1'},
      );
      expect(switchOf(tester, '2').value, isFalse);

      await chooseFromMenu(tester, '2', 'assign_species');
      await tester.tap(
        find.byKey(const Key('edit_deck_subdeck_species_tile_a')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('edit_deck_subdeck_species_confirm_button')),
      );
      await tester.pumpAndSettle();

      expect(switchOf(tester, '1').value, isTrue);
      expect(switchOf(tester, '2').value, isTrue);
    });

    testWidgets('the last filled subdeck stays on beside an empty one', (
      tester,
    ) async {
      await pumpPage(
        tester,
        speciesIds: ['a'],
        subdeckBySpecies: {'a': '1'},
      );

      await addSubdeck(tester, 'Empty');

      expect(switchOf(tester, '1').onChanged, isNull);
    });

    testWidgets('removing a species takes it out of its subdeck\'s count', (
      tester,
    ) async {
      await pumpPage(
        tester,
        speciesIds: ['a', 'b'],
        subdeckBySpecies: {'a': '1', 'b': '1'},
      );
      expect(find.text('2 species'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove').first);
      await tester.pumpAndSettle();

      expect(find.text('1 species'), findsOneWidget);
      });
  });

  testWidgets('a user who saw the learning settings coach mark gets the '
      'subdeck one alone', (tester) async {
    final prefs = await pumpPage(
      tester,
      speciesIds: ['a'],
      subdeckBySpecies: {'a': '1'},
      hasSeenSubdeckTutorial: false,
    );
    // The coach mark never stops animating, so no pumpAndSettle.
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(
      find.textContaining('This deck is divided into subdecks'),
      findsOneWidget,
    );
    expect(find.textContaining('Here you choose whether'), findsNothing);
    expect(prefs.hasSeenEditDeckSubdecksTutorial, isTrue);
  });
}
