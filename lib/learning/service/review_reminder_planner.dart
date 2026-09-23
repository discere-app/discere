/// One daily review reminder: when it fires, and how many cards are due by
/// then.
class ReviewReminder {
  final DateTime scheduledAt;
  final int dueCount;

  const ReviewReminder({required this.scheduledAt, required this.dueCount});
}

/// Turns a deck's card due dates into the reminders that should be scheduled
/// for the days ahead.
///
/// Pure: no plugin, no database, no clock of its own — [plan] takes [now] as
/// an argument so the day boundaries it draws can be checked directly.
class ReviewReminderPlanner {
  const ReviewReminderPlanner();

  /// One reminder per day that has cards due, at [preferredHour]:
  /// [preferredMinute], for the next [daysAhead] days.
  ///
  /// Today is counted differently from the days after it: its reminder
  /// covers everything due by the end of today, overdue cards included,
  /// because those are what the user would sit down to review now. A future
  /// day counts only the cards that come due on that day — the ones from
  /// earlier days will have had their own reminder.
  ///
  /// Days without due cards are left out rather than producing a reminder
  /// saying zero. A reminder whose time has already passed today is left out
  /// too, since scheduling it would either fire immediately or be dropped.
  List<ReviewReminder> plan({
    required List<DateTime?> cardDueDates,
    required DateTime now,
    required int preferredHour,
    int preferredMinute = 0,
    int daysAhead = 14,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final reminders = <ReviewReminder>[];

    for (var i = 0; i < daysAhead; i++) {
      final day = today.add(Duration(days: i));
      final nextDay = day.add(const Duration(days: 1));

      final count = cardDueDates.where((date) {
        if (date == null || !date.isBefore(nextDay)) return false;
        return i == 0 || date.isAfter(day);
      }).length;
      if (count == 0) continue;

      final scheduledAt = DateTime(
        day.year,
        day.month,
        day.day,
        preferredHour,
        preferredMinute,
      );
      if (scheduledAt.isBefore(now)) continue;

      reminders.add(ReviewReminder(scheduledAt: scheduledAt, dueCount: count));
    }

    return reminders;
  }
}
