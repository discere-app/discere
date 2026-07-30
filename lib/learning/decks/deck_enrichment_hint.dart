import 'package:discere/enrichment/queue/presentation/enrichment_state_style.dart';
import 'package:discere/enrichment/queue/presentation/enrichment_status_visual.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/ui/notification_permission_dialog.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:discere/theme/ocean_theme/ocean_colors.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// One-line enrichment status shown on a deck card: current state with icon,
/// a tap-to-explain dialog listing all states, and a retry button when the
/// last enrichment attempt failed.
class DeckEnrichmentHint extends StatefulWidget {
  final String deckId;

  const DeckEnrichmentHint({required this.deckId, super.key});

  @override
  State<DeckEnrichmentHint> createState() => _DeckEnrichmentHintState();
}

class _DeckEnrichmentHintState extends State<DeckEnrichmentHint> {
  static const _style = EnrichmentStateStyle();

  bool _isRetrying = false;

  static const List<DeckEnrichmentState> _explainedStatesInOrder = [
    DeckEnrichmentState.pending,
    DeckEnrichmentState.loadingBase,
    DeckEnrichmentState.loadingExtended,
    DeckEnrichmentState.done,
    DeckEnrichmentState.doneWithGaps,
    DeckEnrichmentState.cooldown,
    DeckEnrichmentState.paused,
    DeckEnrichmentState.failed,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Selector<INatEnrichmentQueueService, DeckEnrichmentInfo>(
      selector: (context, service) => service.deckInfo(widget.deckId),
      builder: (context, info, child) {
        if (info.state == DeckEnrichmentState.hidden) {
          if (info.lastCompletedAt == null && info.lastAttemptedAt == null) {
            return const SizedBox.shrink();
          }
        }

        final hint = _hintFor(context, info);
        if (hint == null) return const SizedBox.shrink();

        final canRetry = info.state == DeckEnrichmentState.failed;

        return Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => _showStateExplainDialog(context, info.state),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(hint.icon, size: 14, color: hint.color),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          hint.text,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: hint.color,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!canRetry) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.info_outline,
                          size: 12,
                          color: hint.color.withValues(alpha: 0.7),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (canRetry)
              _isRetrying
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      key: Key('deck_card_inat_retry_button_${widget.deckId}'),
                      icon: const Icon(Icons.refresh, size: 18),
                      color: hint.color,
                      tooltip: context.loc.commonRetry,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _retry(info),
                    ),
          ],
        );
      },
    );
  }

  Future<void> _retry(DeckEnrichmentInfo info) async {
    setState(() => _isRetrying = true);
    try {
      await ensureNotificationPermission(context);
      if (!mounted) return;

      await Provider.of<INatEnrichmentQueueService>(
        context,
        listen: false,
      ).scheduleDeckEnrichment(
        [widget.deckId],
        includeINatPhotos: info.includesINatPhotos,
        includeCommonNames: info.includesCommonNames,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.loc.editDeckINatEnrichmentError(e.toString()),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isRetrying = false);
    }
  }

  void _showStateExplainDialog(
    BuildContext context,
    DeckEnrichmentState current,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final loc = dialogContext.loc;
        return AlertDialog(
          title: Text(loc.inatDeckStateExplainTitle),
          contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final state in _explainedStatesInOrder)
                  _StateExplainRow(state: state, isCurrent: state == current),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(loc.commonOk),
            ),
          ],
        );
      },
    );
  }

  EnrichmentStatusVisual? _hintFor(
    BuildContext context,
    DeckEnrichmentInfo info,
  ) {
    final loc = context.loc;
    final icon = _style.iconFor(info.state);
    final color = _style.colorFor(info.state);
    switch (info.state) {
      case DeckEnrichmentState.hidden:
        if (info.lastCompletedAt != null) {
          return EnrichmentStatusVisual(
            text: _formatLastCompleted(context, info.lastCompletedAt!),
            icon: Icons.check_circle_outline,
            color: color,
          );
        }
        return null;
      case DeckEnrichmentState.loadingBase:
        return EnrichmentStatusVisual(
          text: info.progressTotal > 0
              ? loc.inatDeckStateLoadingBaseProgress(
                  info.progressCompleted,
                  info.progressTotal,
                )
              : loc.inatDeckStateLoadingBase,
          icon: icon,
          color: color,
        );
      case DeckEnrichmentState.loadingExtended:
        return EnrichmentStatusVisual(
          text: info.progressTotal > 0
              ? loc.inatDeckStateLoadingExtendedProgress(
                  info.progressCompleted,
                  info.progressTotal,
                )
              : loc.inatDeckStateLoadingExtended,
          icon: icon,
          color: color,
        );
      case DeckEnrichmentState.done:
        return EnrichmentStatusVisual(
          text: info.lastCompletedAt != null
              ? _formatLastCompleted(context, info.lastCompletedAt!)
              : loc.inatDeckStateDone,
          icon: icon,
          color: color,
        );
      case DeckEnrichmentState.pending:
      case DeckEnrichmentState.doneWithGaps:
      case DeckEnrichmentState.cooldown:
      case DeckEnrichmentState.paused:
      case DeckEnrichmentState.failed:
        return EnrichmentStatusVisual(
          text: _style.labelFor(info.state, loc),
          icon: icon,
          color: color,
        );
    }
  }

  String _formatLastCompleted(BuildContext context, DateTime completedAt) {
    final difference = DateTime.now().difference(completedAt);
    if (difference.inMinutes < 1) {
      return context.loc.inatDeckStatusUpdatedNow;
    }
    if (difference.inHours < 1) {
      return context.loc.inatDeckStatusUpdatedMinutes(difference.inMinutes);
    }
    if (difference.inDays < 1) {
      return context.loc.inatDeckStatusUpdatedHours(difference.inHours);
    }
    return context.loc.inatDeckStatusUpdatedDays(difference.inDays);
  }
}

class _StateExplainRow extends StatelessWidget {
  static const _style = EnrichmentStateStyle();

  final DeckEnrichmentState state;
  final bool isCurrent;

  const _StateExplainRow({required this.state, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    final theme = Theme.of(context);
    final icon = _style.iconFor(state);
    final color = _style.colorFor(state);
    final label = _style.labelFor(state, loc);
    final description = _style.descriptionFor(state, loc);

    return Container(
      decoration: BoxDecoration(
        color: isCurrent ? color.withValues(alpha: 0.08) : null,
        border: Border(
          left: BorderSide(
            color: isCurrent ? color : OceanColors.transparent,
            width: 3,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s16,
        vertical: AppSpacing.s12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isCurrent) ...[
                      const SizedBox(width: AppSpacing.s8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          loc.inatDeckStateExplainCurrent,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(description, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
