import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Offers to refresh already-downloaded base images once, on the first
/// home screen after a start that installed a reference database — a cold
/// start or the restart that applies a staged update — so the images are
/// fetched again against the database now open. Called from
/// `MainScreenPage` before its onboarding and tutorial. Skipped entirely
/// when nothing is actually stale, so a user with no decks yet (or one whose
/// species already happen to be current) never sees an empty prompt.
Future<void> maybeShowBaseRefreshPrompt(BuildContext context) async {
  final enrichmentQueue = Provider.of<INatEnrichmentQueueService>(
    context,
    listen: false,
  );
  final staleCount = await enrichmentQueue.countStaleBaseSpeciesGlobally();
  if (staleCount == 0 || !context.mounted) return;

  final loc = context.loc;
  final refreshNow = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        icon: const Icon(Icons.image_outlined, size: 32),
        title: Text(loc.referenceDbBaseRefreshPromptTitle),
        content: Text(loc.referenceDbBaseRefreshPromptMessage(staleCount)),
        actions: [
          TextButton(
            key: const Key('base_refresh_prompt_later_button'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(loc.referenceDbBaseRefreshPromptLater),
          ),
          FilledButton(
            key: const Key('base_refresh_prompt_now_button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(loc.referenceDbBaseRefreshPromptNow),
          ),
        ],
      );
    },
  );
  if (refreshNow == true && context.mounted) {
    await enrichmentQueue.refreshAllStaleBaseImages();
  }
}
