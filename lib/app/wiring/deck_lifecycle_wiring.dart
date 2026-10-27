import 'dart:async';

import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/learning/model/review_mode.dart';
import 'package:discere/learning/repository/deck_config_repository.dart';
import 'package:discere/learning/service/deck_lifecycle_observer.dart';
import 'package:discere/shared/persistence/user_data_writes.dart';
import 'package:discere/shared/service/user_preferences_service.dart';

/// Fans deck lifecycle events out to the slices that own the follow-up work:
/// a new deck gets its `deck_config` row, a deleted one has its queued
/// enrichment cancelled.
///
/// [cancelDeckEnrichment] is filled in by the composition root once the
/// enrichment queue exists. The two slices depend on each other — enrichment
/// needs the deck service to resolve a deck's species, the deck service
/// needs enrichment to cancel work — so one direction cannot be wired at
/// construction time. That this is the one late binding, and that it sits in
/// the composition root rather than as a mutable field on DecksService, is
/// the point: every other caller gets an observer it cannot forget.
class DeckLifecycleWiring implements DeckLifecycleObserver {
  final DeckConfigRepository _deckConfigRepository;
  final UserPreferencesService _userPreferences;
  final UserDataWrites _writes;

  /// Set by the composition root after the enrichment queue is built.
  /// Absent until then, which only covers the window before the app runs.
  void Function(String deckId)? cancelDeckEnrichment;

  DeckLifecycleWiring({
    required DeckConfigRepository deckConfigRepository,
    required UserPreferencesService userPreferences,
    required UserDataWrites userDataWrites,
  }) : _deckConfigRepository = deckConfigRepository,
       _userPreferences = userPreferences,
       _writes = userDataWrites;

  @override
  void onDeckCreated(
    String deckId, {
    LearningMode? learningMode,
    NameType? nameType,
    ReviewMode? reviewMode,
  }) {
    // Not awaited by the deck service, so counted here: a restart must not
    // close the database before the new deck has its configuration. The
    // settings the deck brings go into this one write, which never
    // overwrites: a merge target keeps the config it takes over from the
    // deck it replaces, whichever of the two is saved first.
    unawaited(
      _writes.run(
        () => _deckConfigRepository.saveIfAbsent(
          DeckConfig(
            deckId: deckId,
            desiredRetention: _userPreferences.defaultDesiredRetention,
          ).copyWith(
            learningMode: learningMode,
            nameType: nameType,
            reviewMode: reviewMode,
          ),
        ),
      ),
    );
  }

  @override
  void onDeckDeleted(String deckId) => cancelDeckEnrichment?.call(deckId);
}
