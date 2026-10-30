import 'package:discere/learning/decks/widgets/deck_action_presenter.dart';
import 'package:discere/learning/model/deck_stat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const presenter = DeckActionPresenter();

  group('DeckActionPresenter.actionFor', () {
    test('reviews the due cards', () {
      final action = presenter.actionFor(DeckStat(150, 0, 12));

      expect(action, isA<DeckActionReview>());
      expect((action as DeckActionReview).dueCount, 12);
      expect(action.canStart, isTrue);
    });

    test('reviews the due cards before new ones while both wait', () {
      final action = presenter.actionFor(DeckStat(150, 120, 12));

      expect(action, isA<DeckActionReview>());
      expect((action as DeckActionReview).dueCount, 12);
    });

    test('learns new cards once nothing is due', () {
      final action = presenter.actionFor(DeckStat(150, 120, 0));

      expect(action, isA<DeckActionLearnNew>());
      expect(action.canStart, isTrue);
    });

    test('has nothing to start when every card is taken up and none is '
        'due', () {
      final action = presenter.actionFor(DeckStat(150, 0, 0));

      expect(action, isA<DeckActionNothingDue>());
      expect(action.canStart, isFalse);
    });

    test('has nothing to start for a deck without a card', () {
      final action = presenter.actionFor(DeckStat(0, 0, 0));

      expect(action, isA<DeckActionNoCards>());
      expect(action.canStart, isFalse);
    });
  });
}
