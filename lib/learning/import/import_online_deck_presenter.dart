import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/service/deck_supersession.dart';
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

  /// Not imported, but it supersedes local decks — offer to merge them into
  /// it instead of an import beside them.
  supersedesLocal,
}

/// Classifies [ImportOnlineDeckStatus] for a catalog entry, given which local
/// decks the catalog stands for or supersedes ([DeckSupersession]). Kept
/// separate from
/// [ImportOnlineDecksTab] so the classification is unit-testable without a
/// widget tree, mirroring the presenter pattern used elsewhere in the app.
class ImportOnlineDeckPresenter {
  const ImportOnlineDeckPresenter();

  ImportOnlineDeckStatus statusFor(
    CreateDeck remote,
    DeckSupersession supersession,
  ) {
    final local = supersession.localDeckOf(remote);
    if (local == null) {
      return supersession.decksSupersededBy(remote).isEmpty
          ? ImportOnlineDeckStatus.notImported
          : ImportOnlineDeckStatus.supersedesLocal;
    }

    return DeckUpdateService.isNewer(
          localUpdatedAt: local.updatedAt,
          remoteUpdatedAt: remote.updatedAt,
        )
        ? ImportOnlineDeckStatus.updateAvailable
        : ImportOnlineDeckStatus.upToDate;
  }
}
