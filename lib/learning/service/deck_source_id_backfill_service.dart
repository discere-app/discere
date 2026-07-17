import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/repository/deck_repository.dart';
import 'package:discere/learning/service/remote_deck_service.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One-time best-effort backfill of `sourceId`/`updatedAt` for decks that
/// were imported before those fields existed, correlated against the
/// current online catalog by exact deck name. Skips decks with no match or
/// an ambiguous (non-unique) name match rather than guessing.
///
/// Temporary migration helper introduced alongside the sourceId/updatedAt
/// columns (app version 1.0.4). Safe to delete — this file and its call
/// site in `bootstrap_app.dart` — once we're confident active installs have
/// run it at least once, e.g. a few releases after 1.0.4.
@Deprecated(
  'Temporary migration helper for the 1.0.4 sourceId/updatedAt rollout. '
  'Remove once active installs have had a chance to run it at least once.',
)
class DeckSourceIdBackfillService {
  static final _log = Logger.forType(DeckSourceIdBackfillService);
  static const _prefKeyDone = 'deck_source_id_backfill_done';

  final DeckRepository _deckRepository;
  final RemoteDeckService _remoteDeckService;

  DeckSourceIdBackfillService(this._deckRepository, this._remoteDeckService);

  /// Runs the backfill if it hasn't successfully completed before. Never
  /// throws: if the catalog can't be fetched (e.g. no network), it is
  /// treated as not-yet-attempted and retried on the next call.
  Future<void> runIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefKeyDone) ?? false) return;

    final localDecks = await _deckRepository.getAllDecks();
    final needsBackfill = localDecks
        .where((deck) => deck.sourceId == null)
        .toList();
    if (needsBackfill.isEmpty) {
      await prefs.setBool(_prefKeyDone, true);
      return;
    }

    final List<CreateDeck> remoteDecks;
    try {
      remoteDecks = await _remoteDeckService.fetchRemoteDecks();
    } catch (e) {
      _log.debug(
        'Deck sourceId backfill: catalog fetch failed, will retry next start: $e',
      );
      return;
    }

    // Null out any name that occurs more than once so an ambiguous match
    // is skipped instead of picking one at random.
    final byName = <String, CreateDeck?>{};
    for (final remote in remoteDecks) {
      byName.update(remote.name, (_) => null, ifAbsent: () => remote);
    }

    var matched = 0;
    for (final local in needsBackfill) {
      final match = byName[local.name];
      if (match?.sourceId == null) continue;
      await _deckRepository.updateSourceMetadata(
        local.id!,
        sourceId: match!.sourceId!,
        updatedAt: match.updatedAt,
      );
      matched++;
    }

    _log.debug(
      'Deck sourceId backfill: matched $matched/${needsBackfill.length} decks',
    );
    await prefs.setBool(_prefKeyDone, true);
  }
}
