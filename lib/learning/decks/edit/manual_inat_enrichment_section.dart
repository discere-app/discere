import 'package:discere/enrichment/presentation/enrichment_status_presenter.dart';
import 'package:discere/enrichment/presentation/enrichment_status_visual.dart';
import 'package:discere/enrichment/service/inat_enrichment_queue_service.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

/// Edit-deck section showing the deck's iNaturalist enrichment status and a
/// button to (re-)trigger it manually. Subscribes to the queue service so
/// the status line updates live while enrichment is running.
class ManualINatEnrichmentSection extends StatelessWidget {
  final String deckId;
  final int speciesCount;
  final bool isSaving;
  final Future<void> Function() onTrigger;

  const ManualINatEnrichmentSection({
    required this.deckId,
    required this.speciesCount,
    required this.isSaving,
    required this.onTrigger,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Selector<INatEnrichmentQueueService, DeckEnrichmentInfo>(
      selector: (context, service) => service.deckInfo(deckId),
      builder: (context, info, child) {
        final hasSpecies = speciesCount > 0;
        final isBusy =
            info.isActive || (info.hasPendingWork && !info.hasFailedAttempt);
        final canTrigger = hasSpecies && !isBusy && !isSaving;
        final status = _statusFor(context, info, hasSpecies);
        final buttonLabel = info.hasCompletedINatEnrichment
            ? context.loc.editDeckINatEnrichmentButtonAgain
            : context.loc.editDeckINatEnrichmentButtonNow;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.loc.editDeckINatEnrichmentTitle,
              style: theme.textTheme.titleSmall,
            ),
            AppSpacing.heightS8,
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.s16),
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(status.icon, size: 20, color: status.color),
                      ),
                      const SizedBox(width: AppSpacing.s12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.loc.editDeckINatEnrichmentStatusLabel,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            AppSpacing.heightS4,
                            Text(
                              status.text,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: status.color,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  AppSpacing.heightS12,
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      key: const Key('edit_deck_inat_enrichment_button'),
                      onPressed: canTrigger ? onTrigger : null,
                      icon: isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_sync_outlined, size: 18),
                      label: Text(buttonLabel),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  EnrichmentStatusVisual _statusFor(
    BuildContext context,
    DeckEnrichmentInfo info,
    bool hasSpecies,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    if (!hasSpecies) {
      return EnrichmentStatusVisual(
        text: context.loc.editDeckINatEnrichmentNoSpecies,
        icon: Icons.info_outline,
        color: colorScheme.onSurfaceVariant,
      );
    }
    if (info.isActive) {
      return EnrichmentStatusVisual(
        text: formatDeckPendingStatusLabel(
          context.loc,
          hasActiveHostCooldown: false,
          progressCompleted: info.progressCompleted,
          progressTotal: info.progressTotal,
        ),
        icon: Icons.cloud_sync_outlined,
        color: colorScheme.primary,
      );
    }
    if (info.hasFailedAttempt) {
      return EnrichmentStatusVisual(
        text: context.loc.editDeckINatEnrichmentFailed,
        icon: Icons.error_outline,
        color: colorScheme.error,
      );
    }
    if (info.hasPendingWork) {
      return EnrichmentStatusVisual(
        text: formatDeckPendingStatusLabel(
          context.loc,
          hasActiveHostCooldown: info.hasActiveHostCooldown,
          progressCompleted: info.progressCompleted,
          progressTotal: info.progressTotal,
        ),
        icon: info.hasActiveHostCooldown
            ? Icons.cloud_off_outlined
            : info.isReady
            ? Icons.check_circle_outline
            : Icons.hourglass_top_outlined,
        color: info.isReady && !info.hasActiveHostCooldown
            ? colorScheme.primary
            : colorScheme.onSurfaceVariant,
      );
    }
    if (info.hasCompletedINatEnrichment) {
      return EnrichmentStatusVisual(
        text: context.loc.editDeckINatEnrichmentLastUpdated(
          _formatDateTime(context, info.lastCompletedAt!),
        ),
        icon: Icons.check_circle_outline,
        color: colorScheme.onSurfaceVariant,
      );
    }
    return EnrichmentStatusVisual(
      text: context.loc.editDeckINatEnrichmentNever,
      icon: Icons.info_outline,
      color: colorScheme.onSurfaceVariant,
    );
  }

  String _formatDateTime(BuildContext context, DateTime dateTime) {
    return DateFormat.yMMMd(
      Localizations.localeOf(context).toLanguageTag(),
    ).add_Hm().format(dateTime);
  }
}
