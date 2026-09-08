import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class ImportOnlineErrorState extends StatelessWidget {
  final String errorMessage;
  final Future<void> Function() onRetry;

  const ImportOnlineErrorState({
    super.key,
    required this.errorMessage,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: AppSpacing.emptyStatePaddingAll,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off,
              size: AppSpacing.emptyStateIconSize,
              color: theme.colorScheme.error.withValues(alpha: 0.7),
            ),
            AppSpacing.heightS24,
            Text(
              context.loc.error,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.error,
              ),
            ),
            AppSpacing.heightS12,
            Text(
              errorMessage,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            AppSpacing.heightS32,
            SizedBox(
              width: 200,
              child: ElevatedButton.icon(
                key: const ValueKey('import-retry-button'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(context.loc.commonRetry),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
