import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/species_detail/species_detail_content.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/flashcard/flashcard_back_content.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String? clipboardText;

  setUp(() {
    clipboardText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              clipboardText = (call.arguments as Map)['text'] as String?;
              return null;
            case 'Clipboard.getData':
              return clipboardText == null ? null : {'text': clipboardText};
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('Species detail copies long-pressed scientific names', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildApp(
        Scaffold(
          body: SpeciesDetailContent(
            species: _sampleSpecies(),
            language: Language.en,
          ),
        ),
      ),
    );

    await tester.longPress(find.text('Amphiprion ocellaris').first);
    await tester.pump();

    expect(clipboardText, 'Amphiprion ocellaris');
  });

  testWidgets('Flashcard back copies long-pressed common names', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildApp(
        Scaffold(
          body: FlashcardBackContent(
            speciesWithLocalImages: _sampleSpecies(),
            language: Language.en,
          ),
        ),
      ),
    );

    await tester.longPress(find.text('Clown anemonefish').first);
    await tester.pump();

    expect(clipboardText, 'Clown anemonefish');
  });
}

SpeciesWithLocalImages _sampleSpecies() {
  return SpeciesWithLocalImages(
    Species(
      'sp1',
      'sp1',
      'fishbase',
      'ocellaris',
      {Language.en: 'Clown anemonefish', Language.de: 'Falscher Clownfisch'},
      Classification(
        'Amphiprion',
        {Language.en: 'Clownfishes'},
        null,
        'Pomacentridae',
        {Language.en: 'Damselfishes'},
        'Perciformes',
        {Language.en: 'Perch-like fishes'},
        'Actinopterygii',
        {Language.en: 'Ray-finned fishes'},
        'Osteichthyes',
      ),
      const [],
    ),
    const [],
  );
}

Widget _buildApp(Widget home) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );
}
