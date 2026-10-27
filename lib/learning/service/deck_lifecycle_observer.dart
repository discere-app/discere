import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/learning/model/review_mode.dart';

/// Notified when a deck comes into existence or goes away, so state owned
/// elsewhere can follow along.
///
/// Two things hang off this today: a new deck needs its `deck_config` row,
/// and a deleted deck's queued enrichment has to be cancelled. Neither
/// belongs to `DecksService` — it knows about decks, not about review
/// settings or the enrichment queue — but both must happen, and the service
/// is the only place that knows when.
///
/// Passed in at construction rather than assigned afterwards: a service
/// built without one used to be a service that silently left enrichment
/// running for deleted decks and created decks without configuration, and
/// nothing in its type said so. [NoopDeckLifecycleObserver] makes "nothing
/// should follow" a choice a caller states out loud.
abstract interface class DeckLifecycleObserver {
  /// A deck was created, manually or by import, to start with
  /// [learningMode], [nameType] and [reviewMode] — one that is `null` starts
  /// at the app's default.
  void onDeckCreated(
    String deckId, {
    LearningMode? learningMode,
    NameType? nameType,
    ReviewMode? reviewMode,
  });

  /// A deck was deleted. Its rows are already gone by the time this runs.
  void onDeckDeleted(String deckId);
}

/// For callers with nothing to follow up — tests, and entry points that
/// never create or delete decks.
class NoopDeckLifecycleObserver implements DeckLifecycleObserver {
  const NoopDeckLifecycleObserver();

  @override
  void onDeckCreated(
    String deckId, {
    LearningMode? learningMode,
    NameType? nameType,
    ReviewMode? reviewMode,
  }) {}

  @override
  void onDeckDeleted(String deckId) {}
}
