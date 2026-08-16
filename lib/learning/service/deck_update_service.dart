import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/repository/deck_repository.dart';
import 'package:discere/learning/service/remote_deck_service.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks which locally-imported decks (those with a `sourceId`) have a newer
/// version available in the online catalog, so the deck list can show an
/// "update available" badge.
///
/// [checkForUpdates] is meant to run once per app start (see
/// `bootstrap_app.dart`'s `startDeferred`), but only actually hits the
/// network at most once every [checkInterval] — the timestamp of the last
/// successful check is persisted in [SharedPreferences] so it survives
/// restarts.
class DeckUpdateService extends ChangeNotifier {
  static final _log = Logger.forType(DeckUpdateService);
  static const _prefKeyLastCheckedAt = 'deck_update_last_checked_at';
  static const checkInterval = Duration(days: 7);

  final DeckRepository _deckRepository;
  final RemoteDeckService _remoteDeckService;
  final SharedPreferences _preferences;

  Map<String, CreateDeck> _availableUpdates = {};

  DeckUpdateService(
    this._deckRepository,
    this._remoteDeckService,
    this._preferences,
  );

  /// The catalog entry newer than what's stored locally for [deckId], or
  /// null if no update is known (either up to date, not catalog-sourced, or
  /// the check hasn't run/succeeded yet).
  CreateDeck? updateFor(String deckId) => _availableUpdates[deckId];

  /// Whether [remoteUpdatedAt] represents newer catalog content than
  /// [localUpdatedAt] — a deck never tracked locally (`localUpdatedAt ==
  /// null`) always counts as outdated; a catalog entry without a timestamp
  /// (`remoteUpdatedAt == null`) never counts as an update. Shared by
  /// [checkForUpdates] and the "Online" import tab, which uses it to offer
  /// an update instead of a duplicate import for decks already tracked.
  static bool isNewer({
    required DateTime? localUpdatedAt,
    required DateTime? remoteUpdatedAt,
  }) {
    if (remoteUpdatedAt == null) return false;
    return localUpdatedAt == null || remoteUpdatedAt.isAfter(localUpdatedAt);
  }

  /// Removes [deckId] from the available-updates map — called once its
  /// update has been reviewed/applied, without waiting for the next
  /// [checkForUpdates] pass to notice.
  void clearUpdate(String deckId) {
    if (_availableUpdates.remove(deckId) != null) {
      notifyListeners();
    }
  }

  /// Fetches the online catalog and compares it against local decks that
  /// carry a `sourceId` — but only if [checkInterval] has passed since the
  /// last successful check, or [force] is set. Never throws: a failed fetch
  /// (e.g. no network) just leaves the previous state untouched and doesn't
  /// count against the interval, matching [DeckSourceIdBackfillService]'s
  /// fire-and-forget error handling.
  Future<void> checkForUpdates({bool force = false}) async {
    if (!force && !_isCheckDue()) return;

    final localDecks = await _deckRepository.getAllDecks();
    final trackedBySourceId = {
      for (final deck in localDecks)
        if (deck.sourceId != null) deck.sourceId!: deck,
    };
    if (trackedBySourceId.isEmpty) return;

    final List<CreateDeck> remoteDecks;
    try {
      remoteDecks = await _remoteDeckService.fetchRemoteDecks();
    } catch (e) {
      _log.debug('Deck update check: catalog fetch failed: $e');
      return;
    }

    final updates = <String, CreateDeck>{};
    for (final remote in remoteDecks) {
      if (remote.sourceId == null) continue;
      final local = trackedBySourceId[remote.sourceId];
      if (local == null) continue;
      if (isNewer(
        localUpdatedAt: local.updatedAt,
        remoteUpdatedAt: remote.updatedAt,
      )) {
        updates[local.id!] = remote;
      }
    }

    _availableUpdates = updates;
    _log.debug('Deck update check: ${updates.length} deck(s) have an update');
    notifyListeners();
    await _preferences.setInt(
      _prefKeyLastCheckedAt,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  bool _isCheckDue() {
    final lastCheckedMillis = _preferences.getInt(_prefKeyLastCheckedAt);
    if (lastCheckedMillis == null) return true;
    final lastChecked = DateTime.fromMillisecondsSinceEpoch(lastCheckedMillis);
    return DateTime.now().difference(lastChecked) >= checkInterval;
  }
}
