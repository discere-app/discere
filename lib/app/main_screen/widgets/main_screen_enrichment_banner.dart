import 'package:discere/enrichment/queue/model/inat_enrichment_status.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Thin strip above the tab content while background enrichment is running.
///
/// Shows itself only when the deck cards cannot already tell the story:
/// once every active deck has at least one image, each card reports its own
/// remaining work and a second, global message would just repeat it. A host
/// cooldown overrides that — nothing is progressing then, and no deck card
/// says why.
class MainScreenEnrichmentBanner extends StatelessWidget {
  const MainScreenEnrichmentBanner({super.key});

  /// Whether [status] is worth a banner. Pure so the rule can be checked
  /// without pumping the widget tree.
  static bool shouldShow(INatEnrichmentStatus status) {
    if (!status.hasPendingWork) return false;
    if (!status.hasActiveHostCooldown &&
        status.readyDeckCount >= status.activeDeckCount) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Selector<INatEnrichmentQueueService, INatEnrichmentStatus>(
      selector: (_, service) => service.status,
      builder: (context, status, child) {
        if (!shouldShow(status)) return const SizedBox.shrink();
        return _Banner(status: status);
      },
    );
  }
}

class _Banner extends StatelessWidget {
  final INatEnrichmentStatus status;

  const _Banner({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = context.loc;
    final label = status.hasActiveHostCooldown
        ? loc.inatBackgroundBannerSourceCooldown
        : status.hasActiveWork
        ? loc.inatBackgroundBannerPreparing
        : loc.inatBackgroundBannerRetryScheduled;

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Icon(
                  Icons.cloud_sync_outlined,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          LinearProgressIndicator(
            minHeight: 2,
            // Indeterminate until the queue knows how much work there is.
            value: status.total > 0
                ? (status.completed / status.total).clamp(0.0, 1.0)
                : null,
          ),
        ],
      ),
    );
  }
}
