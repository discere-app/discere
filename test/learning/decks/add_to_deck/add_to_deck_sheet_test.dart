import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/decks/add_to_deck/add_to_deck_sheet.dart';
import 'package:discere/learning/decks/deck_view_model.dart';
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
}
