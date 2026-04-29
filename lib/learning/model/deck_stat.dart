import 'dart:core';

class DeckStat {
  final int totalCount;
  final int uninitializedCount;
  final int dueCount;

  /// How many new cards have been introduced today.
  final int todayNewCount;

  /// How many review cards have been shown today.
  final int todayReviewCount;

  DeckStat(
    this.totalCount,
    this.uninitializedCount,
    this.dueCount, {
    this.todayNewCount = 0,
    this.todayReviewCount = 0,
  });
}
