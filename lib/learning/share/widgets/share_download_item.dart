import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:discere/theme/app_theme_extension.dart';
import 'package:discere/theme/ocean_theme/ocean_colors.dart';
import 'package:flutter/material.dart';

enum DownloadStatus { idle, loading, success, error }

/// The "save as file" option. Unlike the other two it reports back — writing
/// to disk can fail quietly, and the share sheet fallback happens without a
/// visible screen change, so the row itself confirms what happened.
class ShareDownloadItem extends StatelessWidget {
  final DownloadStatus status;
  final VoidCallback onTap;

  const ShareDownloadItem({
    required this.status,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSuccess = status == DownloadStatus.success;

    return InkWell(
      onTap: status == DownloadStatus.idle ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: AppSpacing.cardPaddingAll,
        decoration: BoxDecoration(
          color: isSuccess
              ? OceanColors.success.withValues(alpha: 0.1)
              : colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSuccess
                ? OceanColors.success.withValues(alpha: 0.5)
                : theme.sectionBorderColor,
            width: isSuccess ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: _StatusIcon(status: status),
            ),
            AppSpacing.widthS16,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.loc.shareDownloadExportJson,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isSuccess
                          ? OceanColors.success
                          : colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    isSuccess
                        ? context.loc.shareDownloadSuccessSubtitle
                        : context.loc.shareDownloadSubtitle,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (status == DownloadStatus.idle)
              Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  final DownloadStatus status;

  const _StatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    switch (status) {
      case DownloadStatus.loading:
        return SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colorScheme.primary,
          ),
        );
      case DownloadStatus.success:
        return const Icon(
          Icons.check_circle,
          color: OceanColors.success,
          key: ValueKey('success'),
        );
      case DownloadStatus.error:
        return Icon(
          Icons.error,
          color: colorScheme.error,
          key: const ValueKey('error'),
        );
      case DownloadStatus.idle:
        return Container(
          key: const ValueKey('idle'),
          padding: AppSpacing.paddingS8All,
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.description, color: colorScheme.primary),
        );
    }
  }
}
