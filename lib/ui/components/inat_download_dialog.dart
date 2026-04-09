import 'package:discere/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../service/learning/decks_service.dart';
import '../../service/learning/inat_enrichment_queue_service.dart';

/// Shows a confirmation dialog and schedules deck enrichment in the background.
///
/// Returns an empty summary because enrichment continues asynchronously after
/// the dialog is dismissed.
Future<ImportEnrichmentSummary> showINatDownloadFlow(
  BuildContext context,
  dynamic deckIdOrIds,
) async {
  final List<String> deckIds = deckIdOrIds is String
      ? [deckIdOrIds]
      : (deckIdOrIds as List).cast<String>();
  if (deckIds.isEmpty) return ImportEnrichmentSummary.empty;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('inat_download_dialog'),
      icon: const Icon(Icons.photo_library_outlined, size: 32),
      title: Text(ctx.loc.inatDialogTitle),
      content: SingleChildScrollView(child: Text(ctx.loc.inatDialogMessage)),
      actions: [
        TextButton(
          key: const Key('inat_skip_button'),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(ctx.loc.inatDialogCancel),
        ),
        FilledButton.icon(
          key: const Key('inat_download_button'),
          onPressed: () => Navigator.of(ctx).pop(true),
          icon: const Icon(Icons.download, size: 18),
          label: Text(ctx.loc.inatDialogConfirm),
        ),
      ],
    ),
  );

  if (!context.mounted) return ImportEnrichmentSummary.empty;

  final enrichmentQueue = Provider.of<INatEnrichmentQueueService>(
    context,
    listen: false,
  );

  enrichmentQueue.scheduleDeckEnrichment(
    deckIds,
    includeINatPhotos: confirmed == true,
    includeCommonNames: confirmed == true,
  );

  return ImportEnrichmentSummary.empty;
}
