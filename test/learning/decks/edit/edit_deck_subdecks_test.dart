import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/enrichment/media/service/species_media_service.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/decks/edit/add_species_sheet.dart';
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

/// Covers the subdeck section of EditDeckPage: part of the draft, saved with
/// the deck, and never leaving the deck without a card.

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
    double width = 1200,
  }) async {
    tester.view.physicalSize = Size(width, 4000);
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
                const SizedBox.shrink(key: Key('species_detail')),
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

    expect(find.widgetWithText(SwitchListTile, 'Level 1'), findsOneWidget);
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
      expect(find.widgetWithText(SwitchListTile, 'First'), findsOneWidget);
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
        tester.getCenter(find.widgetWithText(SwitchListTile, 'Level 2')).dy,
        lessThan(
          tester.getCenter(find.widgetWithText(SwitchListTile, 'Level 1')).dy,
        ),
      );
      expect(saveEnabled(tester), isTrue);

      await dragHandle('1', -rowHeight * 1.2);
      expect(saveEnabled(tester), isFalse);

      await dragHandle('1', rowHeight * 1.2);
      await save(tester);
      expect(savedEdit().subdecks.map((s) => s.id), ['2', '1']);
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

    testWidgets('a species removed and added again is in no subdeck', (
      tester,
    ) async {
      await pumpPage(
        tester,
        speciesIds: ['a', 'b'],
        subdeckBySpecies: {'a': '1', 'b': '1'},
      );

      // Sorted by name: 'Genus a' first.
      await tester.tap(find.byTooltip('Remove').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit_deck_add_species_button')));
      await tester.pumpAndSettle();
      Navigator.of(
        tester.element(find.byType(AddSpeciesSheet)),
      ).pop(_species('a'));
      await tester.pumpAndSettle();

      expect(find.text('1 species'), findsOneWidget);
      expect(saveEnabled(tester), isTrue);
    });
  });

  group('selecting species', () {
    final count = find.byKey(const Key('edit_deck_selection_count'));
    final selectButton = find.byKey(
      const Key('edit_deck_select_species_button'),
    );
    final addButton = find.byKey(const Key('edit_deck_add_species_button'));
    final deleteButton = find.byKey(
      const Key('edit_deck_selection_delete_button'),
    );
    final assignButton = find.byKey(
      const Key('edit_deck_selection_assign_button'),
    );

    String countText(WidgetTester tester) => tester.widget<Text>(count).data!;

    bool isEnabled(WidgetTester tester, Finder button) =>
        tester.widget<IconButton>(button).onPressed != null;

    Checkbox checkbox(WidgetTester tester, String speciesId) =>
        tester.widget<Checkbox>(
          find.byKey(Key('edit_deck_species_checkbox_$speciesId')),
        );

    Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Future<void> tapRow(WidgetTester tester, String speciesId) =>
        tapAndSettle(tester, find.byKey(ValueKey(speciesId)));

    Future<void> startSelecting(WidgetTester tester, List<String> ids) async {
      await tapAndSettle(tester, selectButton);
      for (final id in ids) {
        await tapRow(tester, id);
      }
    }

    Future<void> openTargets(WidgetTester tester) =>
        tapAndSettle(tester, assignButton);

    Future<void> chooseTarget(WidgetTester tester, String target) =>
        tapAndSettle(
          tester,
          find.byKey(Key('edit_deck_subdeck_target_$target')),
        );

    Finder footer(String speciesId) =>
        find.byKey(Key('edit_deck_species_subdeck_$speciesId'));

    String footerText(WidgetTester tester, String speciesId) =>
        tester.widget<Text>(footer(speciesId)).data!;

    testWidgets('the button starts selecting with nothing selected, hides the '
        'header buttons and shows the app bar with its actions off', (tester) async {
      await pumpPage(
        tester,
        speciesIds: ['a', 'b'],
        subdeckBySpecies: {'a': '1'},
      );
      expect(count, findsNothing);

      await tapAndSettle(tester, selectButton);

      expect(countText(tester), '0 selected');
      expect(selectButton.hitTestable(), findsNothing);
      expect(addButton.hitTestable(), findsNothing);
      expect(isEnabled(tester, deleteButton), isFalse);
      expect(isEnabled(tester, assignButton), isFalse);
      expect(checkbox(tester, 'a').value, isFalse);
      expect(find.byTooltip('Remove'), findsNothing);
    });

    testWidgets('the selection takes over the app bar, without moving the '
        'page, and saving comes back with its end', (tester) async {
      await pumpPage(
        tester,
        speciesIds: ['a', 'b'],
        subdeckBySpecies: {'a': '1'},
      );
      final saveButton = find.byKey(const Key('edit_deck_save_button'));
      final nameField = find.byKey(const Key('edit_deck_name_field'));
      final nameFieldTop = tester.getTopLeft(nameField).dy;
      expect(saveButton, findsOneWidget);

      await tapAndSettle(tester, selectButton);

      expect(saveButton, findsNothing);
      expect(find.byIcon(Icons.arrow_back), findsNothing);
      expect(
        find.descendant(of: find.byType(AppBar), matching: count),
        findsOneWidget,
      );
      expect(tester.getTopLeft(nameField).dy, nameFieldTop);

      await tapAndSettle(
        tester,
        find.byKey(const Key('edit_deck_selection_close_button')),
      );

      expect(saveButton, findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(tester.getTopLeft(nameField).dy, nameFieldTop);
    });

    testWidgets('a long press starts selecting with that species', (
      tester,
    ) async {
      await pumpPage(
        tester,
        speciesIds: ['a', 'b'],
        subdeckBySpecies: {'a': '1'},
      );

      await tester.longPress(find.byKey(const ValueKey('b')));
      await tester.pumpAndSettle();

      expect(countText(tester), '1 selected');
      expect(checkbox(tester, 'b').value, isTrue);
      expect(checkbox(tester, 'a').value, isFalse);
      expect(isEnabled(tester, deleteButton), isTrue);
      expect(isEnabled(tester, assignButton), isTrue);
    });

    testWidgets('the rows stay put when a long press starts a selection and '
        'when it ends, also where the header buttons wrap', (tester) async {
      await pumpPage(
        tester,
        speciesIds: ['a', 'b'],
        subdeckBySpecies: {'a': '1'},
        width: 420,
      );
      final row = find.byKey(const ValueKey('b'));
      final rowTop = tester.getTopLeft(row).dy;
      expect(
        tester.getTopLeft(selectButton).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.text('Species in Deck (2)')).dy),
        reason: 'the buttons have to wrap for the jump to be possible',
      );

      await tester.longPress(row);
      await tester.pumpAndSettle();

      expect(countText(tester), '1 selected');
      expect(tester.getTopLeft(row).dy, rowTop);

      await tapAndSettle(
        tester,
        find.byKey(const Key('edit_deck_selection_close_button')),
      );

      expect(count, findsNothing);
      expect(tester.getTopLeft(row).dy, rowTop);
    });

    testWidgets('during a selection the hidden header buttons can be neither '
        'tapped nor reached by a screen reader', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpPage(
        tester,
        speciesIds: ['a', 'b'],
        subdeckBySpecies: {'a': '1'},
      );
      final selectLabel = find.semantics.byLabel('Select');
      final addLabel = find.semantics.byLabel('Add Species');
      expect(selectLabel, findsOneWidget);
      expect(addLabel, findsOneWidget);

      await tester.longPress(find.byKey(const ValueKey('b')));
      await tester.pumpAndSettle();

      expect(selectLabel, findsNothing);
      expect(addLabel, findsNothing);

      await tester.tap(addButton, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(AddSpeciesSheet), findsNothing);

      await tester.tap(selectButton, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(countText(tester), '1 selected');
      expect(checkbox(tester, 'b').value, isTrue);
      semantics.dispose();
    });

    testWidgets('a tap opens the species only outside a selection', (
      tester,
    ) async {
      await pumpPage(
        tester,
        speciesIds: ['a', 'b'],
        subdeckBySpecies: {'a': '1'},
      );

      await startSelecting(tester, ['a']);

      expect(find.byKey(const Key('species_detail')), findsNothing);
      expect(checkbox(tester, 'a').value, isTrue);

      // Deselecting the last one keeps the selection going.
      await tapRow(tester, 'a');
      expect(countText(tester), '0 selected');

      await tapAndSettle(
        tester,
        find.byKey(const Key('edit_deck_selection_close_button')),
      );
      expect(count, findsNothing);
      await tapRow(tester, 'a');
      expect(find.byKey(const Key('species_detail')), findsOneWidget);
    });

    testWidgets('select all takes every species, and again none', (
      tester,
    ) async {
      await pumpPage(
        tester,
        speciesIds: ['a', 'b', 'c'],
        subdeckBySpecies: {'a': '1'},
      );
      final all = find.byKey(const Key('edit_deck_selection_all_button'));

      await startSelecting(tester, ['a']);
      await tapAndSettle(tester, all);
      expect(countText(tester), '3 selected');

      await tapAndSettle(tester, all);
      expect(countText(tester), '0 selected');
      expect(count, findsOneWidget);
    });

    testWidgets('deleting removes exactly the selected, asks nothing, ends the '
        'selection and saves as a removal, not an edit', (tester) async {
      await pumpPage(
        tester,
        speciesIds: ['a', 'b', 'c'],
        subdeckBySpecies: {'a': '1', 'c': '2'},
      );

      await startSelecting(tester, ['a', 'b']);
      await tapAndSettle(tester, deleteButton);

      expect(find.byType(AlertDialog), findsNothing);
      expect(count, findsNothing);
      expect(find.byKey(const ValueKey('a')), findsNothing);
      expect(find.byKey(const ValueKey('b')), findsNothing);
      expect(find.byKey(const ValueKey('c')), findsOneWidget);

      await save(tester);
      expect(
        verify(
          decksService.updateDeck(
            any,
            addedSpeciesIds: anyNamed('addedSpeciesIds'),
            removedSpeciesIds: captureAnyNamed('removedSpeciesIds'),
          ),
        ).captured.single,
        {'a', 'b'},
      );
      verifyNever(decksService.editSubdecks(any, any));
    });

    testWidgets('a deleted species comes back in no subdeck', (tester) async {
      await pumpPage(
        tester,
        speciesIds: ['a', 'b'],
        subdeckBySpecies: {'a': '1', 'b': '1'},
      );

      await startSelecting(tester, ['a']);
      await tapAndSettle(tester, deleteButton);
      await tapAndSettle(tester, addButton);
      Navigator.of(
        tester.element(find.byType(AddSpeciesSheet)),
      ).pop(_species('a'));
      await tester.pumpAndSettle();

      expect(footer('a'), findsNothing);
      expect(footer('b'), findsOneWidget);
    });

    testWidgets('deleting the last species outside the subdecks while all are '
        'off switches them on', (tester) async {
      await pumpPage(
        tester,
        speciesIds: ['a', 'free'],
        subdeckBySpecies: {'a': '2'},
      );
      await tester.tap(find.byKey(const Key('edit_deck_subdeck_switch_1')));
      await tester.pumpAndSettle();
      expect(switchOf(tester, '1').value, isFalse);
      expect(switchOf(tester, '2').value, isFalse);

      await startSelecting(tester, ['free']);
      await tapAndSettle(tester, deleteButton);

      expect(switchOf(tester, '1').value, isTrue);
      expect(switchOf(tester, '2').value, isTrue);
    });

    testWidgets('assigning to an existing subdeck moves the selected and saves '
        'them as moves', (tester) async {
      await pumpPage(
        tester,
        speciesIds: ['a', 'b', 'free'],
        subdeckBySpecies: {'a': '1', 'b': '2'},
      );

      await startSelecting(tester, ['a', 'free']);
      await openTargets(tester);
      await chooseTarget(tester, '2');

      expect(count, findsNothing);
      expect(footerText(tester, 'free'), 'Level 2');
      await save(tester);
      expect(savedEdit().moves, {'a': '2', 'free': '2'});
    });

    testWidgets('assigning to no subdeck takes them out', (tester) async {
      await pumpPage(
        tester,
        speciesIds: ['a', 'b'],
        subdeckBySpecies: {'a': '1', 'b': '1'},
      );

      await startSelecting(tester, ['a']);
      await openTargets(tester);
      await chooseTarget(tester, 'none');

      expect(footer('a'), findsNothing);
      await save(tester);
      expect(savedEdit().moves, {'a': null});
    });

    testWidgets('assigning to a new subdeck adds it, on, and moves them in one '
        'step', (tester) async {
      await pumpPage(
        tester,
        speciesIds: ['a', 'b'],
        subdeckBySpecies: {'a': '1'},
      );

      await startSelecting(tester, ['a', 'b']);
      await openTargets(tester);
      await chooseTarget(tester, 'new');
      await enterName(tester, 'Mine');
      await confirmName(tester);

      expect(footerText(tester, 'b'), 'Mine');
      await save(tester);
      final edit = savedEdit();
      final newId = edit.subdecks.last.id;
      expect(edit.subdecks.last.name, 'Mine');
      expect(edit.moves, {'a': newId, 'b': newId});
      expect(
        verify(
          decksService.setActiveSubdecks('deck-1', captureAny),
        ).captured.single,
        contains(newId),
      );
    });

    testWidgets('a deck without subdecks is offered a new one, and no "no '
        'subdeck"', (tester) async {
      when(decksService.getSubdecks('deck-1')).thenAnswer((_) async => []);
      await pumpPage(tester, speciesIds: ['a'], subdeckBySpecies: {});

      await startSelecting(tester, ['a']);
      await openTargets(tester);

      expect(
        find.byKey(const Key('edit_deck_subdeck_target_none')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('edit_deck_subdeck_target_new')),
        findsOneWidget,
      );
    });

    testWidgets('cancelling the sheet or the name dialog changes nothing and '
        'keeps the selection', (tester) async {
      await pumpPage(
        tester,
        speciesIds: ['a', 'b'],
        subdeckBySpecies: {'a': '1', 'b': '1'},
      );
      await startSelecting(tester, ['a']);

      await openTargets(tester);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(countText(tester), '1 selected');

      await openTargets(tester);
      await chooseTarget(tester, 'new');
      await tapAndSettle(tester, find.text('Cancel'));
      expect(countText(tester), '1 selected');
      expect(footerText(tester, 'a'), 'Level 1');

      await tapAndSettle(
        tester,
        find.byKey(const Key('edit_deck_selection_close_button')),
      );
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('moving the last cards into a subdeck that is off switches '
        'all on', (tester) async {
      await pumpPage(
        tester,
        speciesIds: ['a'],
        subdeckBySpecies: {'a': '1'},
      );
      expect(switchOf(tester, '2').value, isFalse);

      await startSelecting(tester, ['a']);
      await openTargets(tester);
      await chooseTarget(tester, '2');

      expect(switchOf(tester, '1').value, isTrue);
      expect(switchOf(tester, '2').value, isTrue);
    });

    testWidgets('a row shows its subdeck, in and out of a selection, following '
        'the draft', (tester) async {
      await pumpPage(
        tester,
        speciesIds: ['a', 'free'],
        subdeckBySpecies: {'a': '1'},
      );

      expect(footerText(tester, 'a'), 'Level 1');
      expect(footer('free'), findsNothing);

      await tapAndSettle(tester, selectButton);
      expect(footerText(tester, 'a'), 'Level 1');
      await tapAndSettle(
        tester,
        find.byKey(const Key('edit_deck_selection_close_button')),
      );

      await chooseFromMenu(tester, '1', 'rename');
      await enterName(tester, 'First');
      await confirmName(tester);
      expect(footerText(tester, 'a'), 'First');

      await chooseFromMenu(tester, '1', 'delete');
      expect(footer('a'), findsNothing);
    });

    for (final (name, endSelection)
        in <(String, Future<void> Function(WidgetTester))>[
          (
            'the close button',
            (tester) => tester.tap(
              find.byKey(const Key('edit_deck_selection_close_button')),
            ),
          ),
          ('the system back', (tester) => tester.binding.handlePopRoute()),
        ]) {
      testWidgets('$name ends the selection and stays, without asking', (
        tester,
      ) async {
        await pumpPage(
          tester,
          speciesIds: ['a', 'b'],
          subdeckBySpecies: {'a': '1'},
        );
        await startSelecting(tester, ['a']);

        await endSelection(tester);
        await tester.pumpAndSettle();

        expect(count, findsNothing);
        expect(find.byType(EditDeckPage), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
      });

      testWidgets('$name on a dirty draft ends the selection first, and only '
          'the next back asks', (tester) async {
        await pumpPage(
          tester,
          speciesIds: ['a', 'b'],
          subdeckBySpecies: {'a': '1'},
        );
        await tester.tap(find.byKey(const Key('edit_deck_subdeck_switch_2')));
        await tester.pumpAndSettle();
        await startSelecting(tester, ['a']);

        await endSelection(tester);
        await tester.pumpAndSettle();
        expect(count, findsNothing);
        expect(find.byType(AlertDialog), findsNothing);

        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
      });
    }
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
      find.textContaining('Here you divide a deck into subdecks'),
      findsOneWidget,
    );
    expect(find.textContaining('Here you choose whether'), findsNothing);
    expect(prefs.hasSeenEditDeckSubdecksTutorial, isTrue);
  });
}
