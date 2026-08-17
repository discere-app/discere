import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/service/deck_update_service.dart';

/// Whether a catalog entry shown in the "Online" import tab has already been
/// imported locally, and if so, whether the local copy is current.
enum ImportOnlineDeckStatus {
  /// No local deck carries this entry's `sourceId` — offer it for import.
  notImported,

  /// Already imported and the local copy is current — not selectable.
  upToDate,

  /// Already imported, but the catalog entry is newer — offer an update
  /// instead of a duplicate import.
  updateAvailable,
}

/// Classifies [ImportOnlineDeckStatus] for a catalog entry, given the local
/// decks already known by `sourceId` (see
/// [DecksService.getDecksBySourceId]). Kept separate from
/// [ImportOnlineDecksTab] so the classification is unit-testable without a
/// widget tree, mirroring the presenter pattern used elsewhere in the app.
class ImportOnlineDeckPresenter {
  const ImportOnlineDeckPresenter();

  ImportOnlineDeckStatus statusFor(
    CreateDeck remote,
    Map<String, BaseDeck> localDecksBySourceId,
  ) {
    final sourceId = remote.sourceId;
    if (sourceId == null) return ImportOnlineDeckStatus.notImported;

    final local = localDecksBySourceId[sourceId];
    if (local == null) return ImportOnlineDeckStatus.notImported;

    return DeckUpdateService.isNewer(
          localUpdatedAt: local.updatedAt,
          remoteUpdatedAt: remote.updatedAt,
        )
        ? ImportOnlineDeckStatus.updateAvailable
        : ImportOnlineDeckStatus.upToDate;
  }
}
