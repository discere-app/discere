import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/ui/notification_permission_dialog.dart';
import 'package:flutter/material.dart';

/// The species-data download choice for a deck — shared by the post-import
/// result dialog and the Edit Deck "download data" trigger, since both let
/// the user pick between the same three options.
enum DeckDownloadChoice {
  /// Don't schedule any enrichment.
  none,

  /// Reference images from FishBase/SeaLifeBase only.
  baseOnly,

  /// Reference images plus iNaturalist photos and common names.
  full,
}

/// Shows the base/full/none download choice as its own dialog, for a deck
/// that already exists (e.g. re-triggering from Edit Deck after the user
/// originally chose not to download anything on import).
Future<DeckDownloadChoice> showDeckDownloadChoiceDialog(
  BuildContext context,
) async {
  final choice = await showDialog<DeckDownloadChoice>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const _DeckDownloadChoiceDialog(),
  );
  return choice ?? DeckDownloadChoice.none;
}

/// Schedules the enrichment matching a [DeckDownloadChoice] for [deckId] —
/// a no-op for [DeckDownloadChoice.none]. Shared by Edit Deck's manual
/// download-choice trigger and the flashcard review "no data downloaded"
/// flow, so both act on a choice the same way.
Future<void> applyDeckDownloadChoice(
  BuildContext context,
  INatEnrichmentQueueService enrichmentQueue,
  String deckId,
  DeckDownloadChoice choice,
) async {
  switch (choice) {
    case DeckDownloadChoice.none:
      return;
    case DeckDownloadChoice.baseOnly:
      await enrichmentQueue.scheduleDeckEnrichment(
        [deckId],
        includeINatPhotos: false,
        includeCommonNames: false,
      );
    case DeckDownloadChoice.full:
      await ensureNotificationPermission(context);
      if (!context.mounted) return;
      await enrichmentQueue.scheduleDeckEnrichment(
        [deckId],
        includeINatPhotos: true,
        includeCommonNames: true,
      );
  }
}

class _DeckDownloadChoiceDialog extends StatelessWidget {
  const _DeckDownloadChoiceDialog();

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    final theme = Theme.of(context);

    return AlertDialog(
      icon: Icon(
        Icons.cloud_sync_outlined,
        size: 32,
        color: theme.colorScheme.primary,
      ),
      title: Text(loc.deckDownloadChoiceTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(loc.importResultDownloadBase, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 6),
            Text(
              loc.importResultDownloadExtra,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              key: const Key('deck_download_choice_full_button'),
              onPressed: () =>
                  Navigator.of(context).pop(DeckDownloadChoice.full),
              icon: const Icon(Icons.download, size: 18),
              label: Text(loc.importResultDownloadFull),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('deck_download_choice_base_only_button'),
              onPressed: () =>
                  Navigator.of(context).pop(DeckDownloadChoice.baseOnly),
              child: Text(loc.importResultDownloadBaseOnly),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const Key('deck_download_choice_none_button'),
              onPressed: () =>
                  Navigator.of(context).pop(DeckDownloadChoice.none),
              child: Text(loc.importResultDownloadNone),
            ),
          ],
        ),
      ],
    );
  }
}
