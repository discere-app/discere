import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Full-area stand-in for content that failed to load: [icon], an error
/// title, [message] and a retry button. [message] is already localized —
/// build it with `describeError`, never from the error's own text.
class RetryableErrorState extends StatelessWidget {
  final IconData icon;
  final String message;
  final VoidCallback onRetry;
  final Key? retryButtonKey;

  const RetryableErrorState({
    super.key,
    required this.icon,
    required this.message,
    required this.onRetry,
    this.retryButtonKey,
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
              icon,
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
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            AppSpacing.heightS32,
            SizedBox(
              width: 200,
              child: ElevatedButton.icon(
                key: retryButtonKey,
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
