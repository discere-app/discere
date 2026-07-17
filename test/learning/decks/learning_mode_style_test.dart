import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/decks/learning_mode_style.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const style = LearningModeStyle();
  late AppLocalizations en;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('labelFor/descriptionFor/iconFor cover every LearningMode', () {
    for (final mode in LearningMode.values) {
      expect(style.labelFor(mode, en), isNotEmpty);
      expect(style.descriptionFor(mode, en), isNotEmpty);
      expect(style.iconFor(mode), isNotNull);
    }
  });

  test('nameType helpers cover every NameType', () {
    for (final type in NameType.values) {
      expect(style.nameTypeLabelFor(type, en), isNotEmpty);
      expect(style.nameTypeDescriptionFor(type, en), isNotEmpty);
      expect(style.nameTypeIconFor(type), isNotNull);
    }
  });

  test('labels are distinct per mode/type (no copy-paste key mixups)', () {
    final labels = LearningMode.values.map((m) => style.labelFor(m, en));
    expect(labels.toSet(), hasLength(LearningMode.values.length));

    final nameTypeLabels = NameType.values.map(
      (t) => style.nameTypeLabelFor(t, en),
    );
    expect(nameTypeLabels.toSet(), hasLength(NameType.values.length));
  });
}
