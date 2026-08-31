import 'dart:async';

import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/learning/decks/deck_download_choice_dialog.dart';
import 'package:discere/learning/import/import_result_dialog.dart';
import 'package:discere/learning/service/deck_import_service.dart';
import 'package:discere/shared/ui/notification_permission_dialog.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

final _log = Logger.scoped('DeckImportFlow');

/// Runs an import action, shows its result, and wires up enrichment/
/// notification consent — shared by [ImportDeckPage] and the first-run
/// onboarding deck picker so both host pages get identical behavior instead
/// of duplicating it.
Future<void> runDeckImportFlow(
  BuildContext context,
  Future<DeckImportResult> Function(DeckImportService service) importAction,
) async {
  _log.debug('Import tapped');
  final result = await importAction(context.read<DeckImportService>());
  if (result.lastError != null) {
    _log.warn(
      'Import failed attempted=${result.attemptedCount} succeeded=${result.successCount}: '
      '${result.lastError}',
    );
  }
  if (!context.mounted) return;

  // The user picks how much species data to download before anything is
  // scheduled - unlike other enrichment entry points, import always shows
  // this dialog, so it doubles as the download consent step.
  _log.debug(
    'Show import result dialog success=${result.successCount}/${result.attemptedCount} '
    'unresolved=${result.unresolvedNames.length}',
  );
  final choice = await showImportResultDialog(context, result);
  if (!context.mounted) return;

  if (result.hasSuccess) {
    switch (choice) {
      case DeckDownloadChoice.none:
        break;
      case DeckDownloadChoice.baseOnly:
        unawaited(
          context.read<INatEnrichmentQueueService>().scheduleDeckEnrichment(
            result.importedDeckIds,
            includeINatPhotos: false,
            includeCommonNames: false,
            coverImageUrlsByDeckId: result.imageUrlByDeckId,
            unresolvedNamesByDeckId: result.unresolvedNamesByDeckId,
          ),
        );
      case DeckDownloadChoice.full:
        await ensureNotificationPermission(context);
        if (!context.mounted) return;
        unawaited(
          context.read<INatEnrichmentQueueService>().scheduleDeckEnrichment(
            result.importedDeckIds,
            includeINatPhotos: true,
            includeCommonNames: true,
            coverImageUrlsByDeckId: result.imageUrlByDeckId,
            unresolvedNamesByDeckId: result.unresolvedNamesByDeckId,
          ),
        );
    }
    Navigator.of(context).pop();
  }
}
