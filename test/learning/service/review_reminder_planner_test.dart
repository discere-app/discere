import 'package:discere/learning/service/review_reminder_planner.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers ReviewReminderPlanner — which days get a review reminder and what
/// each one counts. Pure, so the day boundaries can be checked against a
/// fixed `now` instead of whatever the clock says during the run.

const _planner = ReviewReminderPlanner();

/// Noon, so a reminder hour can be placed on either side of "now" within the
/// same day.
final _now = DateTime(2026, 3, 10, 12);

DateTime _at(int dayOffset, [int hour = 9]) =>
    DateTime(2026, 3, 10 + dayOffset, hour);

void main() {
  test('leaves out days without due cards instead of announcing zero', () {
    final reminders = _planner.plan(
      cardDueDates: [_at(2)],
      now: _now,
      preferredHour: 19,
      daysAhead: 4,
    );

    expect(reminders, hasLength(1));
    expect(reminders.single.scheduledAt, DateTime(2026, 3, 12, 19));
    expect(reminders.single.dueCount, 1);
  });

  test("today's reminder counts overdue cards as well", () {
    final reminders = _planner.plan(
      cardDueDates: [
        _at(-3), // long overdue
        _at(0, 8), // earlier today
        _at(0, 23), // later today
      ],
      now: _now,
      preferredHour: 19,
      daysAhead: 2,
    );

    expect(reminders.first.scheduledAt, DateTime(2026, 3, 10, 19));
    expect(reminders.first.dueCount, 3);
  });

  test('a future day counts only the cards coming due on that day', () {
    final reminders = _planner.plan(
      cardDueDates: [_at(1, 8), _at(1, 20), _at(2, 8)],
      now: _now,
      preferredHour: 19,
      daysAhead: 5,
    );

    expect(reminders.map((r) => r.dueCount), [2, 1]);
    expect(reminders.map((r) => r.scheduledAt), [
      DateTime(2026, 3, 11, 19),
      DateTime(2026, 3, 12, 19),
    ]);
  });

  test('skips today when its preferred time has already passed', () {
    final reminders = _planner.plan(
      cardDueDates: [_at(0, 8), _at(1, 8)],
      now: _now,
      preferredHour: 9, // 09:00, and it is already noon
      daysAhead: 3,
    );

    expect(reminders, hasLength(1));
    expect(reminders.single.scheduledAt, DateTime(2026, 3, 11, 9));
  });

  test('stops at the horizon it was given', () {
    final reminders = _planner.plan(
      cardDueDates: [_at(1), _at(2), _at(3)],
      now: _now,
      preferredHour: 19,
      daysAhead: 3,
    );

    expect(reminders, hasLength(2));
  });

  test('ignores cards that have no due date', () {
    final reminders = _planner.plan(
      cardDueDates: [null, _at(1), null],
      now: _now,
      preferredHour: 19,
      daysAhead: 3,
    );

    expect(reminders.single.dueCount, 1);
  });

  test('honours the preferred minute', () {
    final reminders = _planner.plan(
      cardDueDates: [_at(1)],
      now: _now,
      preferredHour: 7,
      preferredMinute: 45,
      daysAhead: 2,
    );

    expect(reminders.single.scheduledAt, DateTime(2026, 3, 11, 7, 45));
  });
}
