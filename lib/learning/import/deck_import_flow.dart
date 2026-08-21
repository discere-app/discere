import 'dart:async';

import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
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

  // Start image downloads and background name resolution immediately,
  // independent of the dialog. This runs completely in the background.
  if (result.hasSuccess) {
    unawaited(
      context.read<INatEnrichmentQueueService>().scheduleDeckEnrichment(
        result.importedDeckIds,
        includeINatPhotos: false,
        includeCommonNames: false,
        coverImageUrlsByDeckId: result.imageUrlByDeckId,
        unresolvedNamesByDeckId: result.unresolvedNamesByDeckId,
      ),
    );
  }

  // Show result dialog while images are already downloading
  _log.debug(
    'Show import result dialog success=${result.successCount}/${result.attemptedCount} '
    'unresolved=${result.unresolvedNames.length}',
  );
  final includeINat = await showImportResultDialog(context, result);
  if (!context.mounted) return;

  if (result.hasSuccess) {
    if (includeINat) {
      await ensureNotificationPermission(context);
      if (!context.mounted) return;
      // Add iNat photos and multilingual names to the running enrichment
      unawaited(
        context.read<INatEnrichmentQueueService>().scheduleDeckEnrichment(
          result.importedDeckIds,
          includeINatPhotos: true,
          includeCommonNames: true,
          coverImageUrlsByDeckId: result.imageUrlByDeckId,
        ),
      );
    }
    Navigator.of(context).pop();
  }
}
