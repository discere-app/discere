import 'package:discere/catalog/comparison/add_to_comparison_presenter.dart';
import 'package:discere/catalog/comparison/model/comparison_list.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const presenter = AddToComparisonPresenter();
  late AppLocalizations de;

  setUpAll(() async {
    de = await AppLocalizations.delegate.load(const Locale('de'));
  });

  group('suggestedName', () {
    test('is the name of a single species', () {
      expect(
        presenter.suggestedName({'Dasyatis pastinaca'}, de),
        'Dasyatis pastinaca',
      );
    });

    test('lists two species', () {
      expect(
        presenter.suggestedName({'Dasyatis pastinaca', 'Taeniura lymma'}, de),
        'Dasyatis pastinaca, Taeniura lymma',
      );
    });

    test('names the first two of more and counts the others', () {
      expect(
        presenter.suggestedName({
          'Dasyatis pastinaca',
          'Taeniura lymma',
          'Myliobatis aquila',
          'Aetobatus narinari',
        }, de),
        'Dasyatis pastinaca, Taeniura lymma und 2 weitere',
      );
    });
  });

  group('a list', () {
    const list = ComparisonList(
      id: 'l1',
      name: 'Rays',
      speciesIds: ['sp-a', 'sp-b'],
    );

    test('holding every species is complete', () {
      expect(presenter.containsAll(list, {'sp-b', 'sp-a'}), isTrue);
      expect(presenter.missingFrom(list, {'sp-b', 'sp-a'}), isEmpty);
    });

    test('missing one of them is not, and says which', () {
      expect(presenter.containsAll(list, {'sp-a', 'sp-c'}), isFalse);
      expect(presenter.missingFrom(list, {'sp-a', 'sp-c'}), {'sp-c'});
    });
  });
}
