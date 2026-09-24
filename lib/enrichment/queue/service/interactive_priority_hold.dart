/// Counts the reasons background enrichment must stand still right now.
///
/// A review session takes a hold while it is open, so the rate-limited
/// iNaturalist consumer does not compete with the card the user is looking
/// at. Holds nest: two sessions overlapping (a deck opened from a deck)
/// means two holds, and the queue only resumes once both are gone.
///
/// The point of the type is that only the edges matter. Entering the mode a
/// second time must not pause the queue again, and leaving it while another
/// hold remains must not resume it — so [acquire] and [release] answer
/// whether *this* call was the transition, and the caller does its work only
/// then.
class InteractivePriorityHold {
  int _holds = 0;

  /// Whether anything currently holds the queue back.
  bool get isActive => _holds > 0;

  /// How many holds are outstanding. For logging; the decisions above are
  /// what [acquire] and [release] return.
  int get holdCount => _holds;

  /// Takes a hold. True when this was the first one, i.e. the queue has to
  /// be stopped now.
  bool acquire() => ++_holds == 1;

  /// Gives a hold back. True when this was the last one, i.e. the queue may
  /// run again.
  ///
  /// Releasing without a matching [acquire] is ignored rather than driving
  /// the count negative: a page that is disposed twice, or disposed after
  /// the service was, would otherwise leave the queue permanently free of a
  /// hold it still owes.
  bool release() {
    if (_holds == 0) return false;
    return --_holds == 0;
  }
}
