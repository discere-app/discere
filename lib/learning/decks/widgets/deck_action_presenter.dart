import 'package:discere/learning/model/deck_stat.dart';

/// What a review session started from the deck card begins with.
sealed class DeckAction {
  const DeckAction();

  /// Whether starting a session now has a card to show.
  bool get canStart;
}

/// The deck's stat has not arrived: the session is offered on the assumption
/// that there is something to do, so the button does not flash
/// disabled→enabled while it loads.
///
/// A stat load that failed stays here until the card gets a new view model.
/// The session reports its own load failures when it opens, so the start
/// stays offered rather than the card claiming a state it does not know.
final class DeckActionPending extends DeckAction {
  const DeckActionPending();

  @override
  bool get canStart => true;
}

/// Due cards come first, whether or not new cards are waiting as well.
final class DeckActionReview extends DeckAction {
  final int dueCount;

  const DeckActionReview(this.dueCount);

  @override
  bool get canStart => true;
}

/// Nothing is due, so the session takes up the next batch of new cards.
final class DeckActionLearnNew extends DeckAction {
  const DeckActionLearnNew();

  @override
  bool get canStart => true;
}

/// Every card has been taken up and none is due yet — one may come due later
/// today.
final class DeckActionNothingDue extends DeckAction {
  const DeckActionNothingDue();

  @override
  bool get canStart => false;
}

/// The deck has no card in its learning mode.
final class DeckActionNoCards extends DeckAction {
  const DeckActionNoCards();

  @override
  bool get canStart => false;
}

/// Decides what the deck card's start button offers, kept free of
/// BuildContext so the order the session works in can be tested directly.
class DeckActionPresenter {
  const DeckActionPresenter();

  /// The action for [stat], or [DeckActionPending] while it is `null`.
  DeckAction actionFor(DeckStat? stat) {
    if (stat == null) return const DeckActionPending();
    if (stat.dueCount > 0) return DeckActionReview(stat.dueCount);
    if (stat.uninitializedCount > 0) return const DeckActionLearnNew();
    if (stat.totalCount > 0) return const DeckActionNothingDue();
    return const DeckActionNoCards();
  }
}
