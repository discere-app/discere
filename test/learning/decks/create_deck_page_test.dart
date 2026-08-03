import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/decks/create_deck_page.dart';
import 'package:discere/shared/service/host_cooldown_tracker.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildApp({Set<String>? initialSpeciesNames}) {
    return Provider<ImageService>.value(
      value: ImageService(
        client: http.Client(),
        hostCooldownTracker: HostCooldownTracker(),
      ),
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: CreateDeckPage(initialSpeciesNames: initialSpeciesNames),
      ),
    );
  }

  testWidgets('leaves the species field empty with no initial names', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());

    final field = tester.widget<TextField>(
      find.byKey(const Key('create_deck_species_field')),
    );
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('prefills the species field, newline-joined', (tester) async {
    await tester.pumpWidget(
      buildApp(
        initialSpeciesNames: {'Carcharodon carcharias', 'Isurus oxyrinchus'},
      ),
    );

    final field = tester.widget<TextField>(
      find.byKey(const Key('create_deck_species_field')),
    );
    final lines = field.controller!.text.split('\n');
    expect(
      lines,
      unorderedEquals(['Carcharodon carcharias', 'Isurus oxyrinchus']),
    );
  });
}
