import 'dart:async';

import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/learning/import/inat_download_dialog.dart';
import 'package:discere/shared/ui/notification_permission_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Offers to fetch iNaturalist photos and common names for species newly
/// added to [deckId] — the bundled reference image is scheduled
/// unconditionally, iNaturalist enrichment only if the user opts in via the
/// download dialog. Shared by [EditDeckPage] (species added through the "Add
/// species" sheet) and the deck-update dialog (species pulled in from a
/// refreshed catalog entry).
///
/// [unresolvedNames] carries species names that don't have a local match yet
/// (e.g. from a catalog refresh) — the enrichment queue resolves them via
/// iNaturalist synonym search and adds any match to the deck once found.
/// Species added through the "Add species" sheet are always already
/// resolved, so [EditDeckPage] never needs to pass this.
Future<void> offerINatEnrichmentForNewSpecies(
  BuildContext context,
  String deckId, {
  List<String> unresolvedNames = const [],
}) async {
  final enrichmentQueue = Provider.of<INatEnrichmentQueueService>(
    context,
    listen: false,
  );
  unawaited(
    enrichmentQueue.scheduleDeckEnrichment(
      [deckId],
      includeINatPhotos: false,
      includeCommonNames: false,
      unresolvedNamesByDeckId: unresolvedNames.isEmpty
          ? const {}
          : {deckId: unresolvedNames},
    ),
  );
  final includeINat = await showINatDownloadDialog(context, [deckId]);
  if (includeINat && context.mounted) {
    await ensureNotificationPermission(context);
    unawaited(
      enrichmentQueue.scheduleDeckEnrichment(
        [deckId],
        includeINatPhotos: true,
        includeCommonNames: true,
      ),
    );
  }
}
