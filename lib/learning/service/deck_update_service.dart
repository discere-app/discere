import 'package:discere/learning/import/remote_deck_service.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/repository/deck_repository.dart';
import 'package:discere/learning/service/deck_supersession.dart';
import 'package:discere/shared/persistence/closed_database_tolerance.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/foundation.dart';

/// Tracks which locally-imported decks (those with a `sourceId`) have a newer
/// version available in the online catalog, so the deck list can show an
/// "update available" badge — or are superseded by another catalog entry
/// ([DeckSupersession]), which the deck list offers to merge them into
/// instead.
///
/// What it knows lives in memory only: [checkForUpdates] runs once per app
/// session, from `AppSession`'s deferred setup, and fetches the catalog every
/// time. The catalog index is small enough for that, and it keeps both hints
/// current in every session without anything to persist between them.
class DeckUpdateService extends ChangeNotifier {
  static final _log = Logger.forType(DeckUpdateService);

  final DeckRepository _deckRepository;
  final RemoteDeckService _remoteDeckService;

  Map<String, CreateDeck> _availableUpdates = {};
  Map<String, CreateDeck> _replacements = {};
  List<CreateDeck> _catalog = const [];

  DeckUpdateService(this._deckRepository, this._remoteDeckService);

  /// The catalog entry newer than what's stored locally for [deckId], or
  /// null if no update is known (either up to date, not catalog-sourced, or
  /// the check hasn't run/succeeded yet).
  CreateDeck? updateFor(String deckId) => _availableUpdates[deckId];

  /// The catalog entry to merge [deckId] into, or null if no entry is known
  /// to supersede it. A superseded deck has no [updateFor]: it is not
  /// updated any more, it is replaced.
  CreateDeck? replacementFor(String deckId) => _replacements[deckId];

  /// The catalog the last successful check fetched — what a merge offered
  /// by [replacementFor] is planned against.
  List<CreateDeck> get catalog => _catalog;

  /// Number of decks currently known to have an available update — shown in
  /// the developer Diagnostics page after a manual re-check.
  int get availableUpdateCount => _availableUpdates.length;

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
  /// carry a `sourceId`; without such a deck there is nothing to compare,
  /// and no request goes out. A failed fetch (e.g. no network) just leaves
  /// the previous state untouched. So does a user database closed underneath
  /// the check — it is fire-and-forget from the session setup — while any
  /// other database error propagates.
  Future<void> checkForUpdates() async {
    final localDecks = await toleratingClosedDatabase(
      _log,
      _deckRepository.getAllDecks,
      whenClosed: const <BaseDeck>[],
    );
    if (!localDecks.any((deck) => deck.sourceId != null)) return;

    final List<CreateDeck> remoteDecks;
    try {
      remoteDecks = await _remoteDeckService.fetchRemoteDecks();
    } catch (e) {
      _log.debug('Deck update check: catalog fetch failed: $e');
      return;
    }

    _catalog = remoteDecks;
    _classify(localDecks);
    _log.debug(
      'Deck update check: ${_availableUpdates.length} deck(s) have an '
      'update, ${_replacements.length} are superseded',
    );
    notifyListeners();
  }

  /// Classifies the local decks again against the [catalog] already
  /// fetched — after a merge has imported, emptied or deleted some of them.
  Future<void> reconcileWithLocalDecks() async {
    _classify(await _deckRepository.getAllDecks());
    notifyListeners();
  }

  void _classify(List<BaseDeck> localDecks) {
    final supersession = DeckSupersession(
      catalog: _catalog,
      localDecks: localDecks,
    );
    final replacements = <String, CreateDeck>{};
    final updates = <String, CreateDeck>{};
    for (final local in localDecks) {
      if (supersession.replacementFor(local) case final replacement?) {
        replacements[local.id!] = replacement;
        continue;
      }
      final remote = _catalog
          .where((entry) => entry.sourceId == local.sourceId)
          .firstOrNull;
      if (local.sourceId == null || remote == null) continue;
      if (isNewer(
        localUpdatedAt: local.updatedAt,
        remoteUpdatedAt: remote.updatedAt,
      )) {
        updates[local.id!] = remote;
      }
    }
    _replacements = replacements;
    _availableUpdates = updates;
  }
}
