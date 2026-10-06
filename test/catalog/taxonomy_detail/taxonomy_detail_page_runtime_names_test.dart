import 'dart:io';

import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/repository/taxonomy_repository.dart';
import 'package:discere/catalog/taxonomy_detail/service/taxonomy_service.dart';
import 'package:discere/catalog/taxonomy_detail/taxonomy_detail_page.dart';
import 'package:discere/catalog/taxonomy_detail/widgets/taxonomy_children_section.dart';
import 'package:discere/catalog/taxonomy_detail/widgets/taxonomy_classification_section.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../repository/runtime_common_names_test_schema.dart';

/// Pomacentridae in the reference-DB fixture: class Teleostei, which the
/// reference DB names in English only, and the genus Amphiprion among its
/// children, which it has no name for at all.
final _pomacentridae = SearchResult(
  id: 'discere:fishbase_family:350',
  name: 'Pomacentridae',
  commonNames: const {},
  type: SearchEntityType.family,
);

Finder _inClassification(String text) => find.descendant(
  of: find.byType(TaxonomyClassificationSection),
  matching: find.text(text),
);

Finder _inChildren(String text) => find.descendant(
  of: find.byType(TaxonomyChildrenSection),
  matching: find.text(text),
);

/// Drives the page through the real service and repository on the test
/// databases, so what is checked is what the repository hands the page.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late Database referenceDb;
  late Database userDb;
  late LanguageService languageService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('taxonomy_page_');
    final referenceDbPath = join(tempDir.path, 'reference.db');
    await File('test/fixtures/discere_reference_test.db').copy(referenceDbPath);
    referenceDb = await openDatabase(referenceDbPath, readOnly: true);
    userDb = await openDatabase(join(tempDir.path, 'user.db'));
    await createRuntimeCommonNamesTable(userDb);

    SharedPreferences.setMockInitialValues({
      LanguageService.sharedPreferencesLanguageKey: Language.de.value,
    });
    languageService = LanguageService(await SharedPreferences.getInstance());
  });

  tearDown(() async {
    await referenceDb.close();
    await userDb.close();
    await tempDir.delete(recursive: true);
  });

  Future<void> insertRuntimeName(String entityKey, String name) {
    return userDb.insert('runtime_common_names', {
      'entity_key': entityKey,
      'entity_type': entityKey.split(':').first,
      'language_code': 'de',
      'name': name,
      'position': 0,
      'fetched_at': 0,
    });
  }

  /// Pumps until [ready] is on screen. The databases answer on real time,
  /// which the test clock does not advance, so each round lets real time pass
  /// before rebuilding.
  Future<void> pumpUntilFound(WidgetTester tester, Finder ready) async {
    for (var round = 0; round < 100 && ready.evaluate().isEmpty; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  Future<void> pumpPage(WidgetTester tester) async {
    final repository = TaxonomyRepository(
      database: referenceDb,
      userDatabase: userDb,
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<TaxonomyService>.value(value: TaxonomyService(repository)),
          ChangeNotifierProvider<LanguageService>.value(value: languageService),
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
          home: TaxonomyDetailPage(searchResult: _pomacentridae),
        ),
      ),
    );
    await pumpUntilFound(tester, find.byType(TaxonomyChildrenSection));
    await pumpUntilFound(tester, _inClassification('Teleostei'));
  }

  testWidgets('with German names, the class row and a child show the names '
      'fetched for them', (tester) async {
    await tester.runAsync(() async {
      await insertRuntimeName('class:teleostei', 'Echte Knochenfische');
      await insertRuntimeName('genus:amphiprion', 'Anemonenfische');
    });

    await pumpPage(tester);
    await pumpUntilFound(tester, _inChildren('Anemonenfische'));

    expect(_inClassification('Echte Knochenfische'), findsWidgets);
    expect(_inClassification('teleosts'), findsNothing);
    expect(_inChildren('Anemonenfische'), findsWidgets);
  });
}
