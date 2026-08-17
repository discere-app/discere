import 'package:discere/learning/service/deck_import_service.dart';
import 'package:discere/shared/extensions/app_exception_localization.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/ui/info_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shows the import result with optional iNat enrichment.
///
/// Returns `true` if the user wants iNat enrichment, `false` otherwise.
Future<bool> showImportResultDialog(
  BuildContext context,
  DeckImportResult result,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ImportResultDialog(result: result),
  );
  return confirmed == true;
}

class _ImportResultDialog extends StatelessWidget {
  final DeckImportResult result;

  const _ImportResultDialog({required this.result});

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    final theme = Theme.of(context);

    final isSingle = result.attemptedCount == 1;
    final summary = isSingle
        ? loc.importResultSummarySingle
        : loc.importResultSummary(result.successCount, result.attemptedCount);
    final warningColor = Colors.orange.shade800;

    return AlertDialog(
      icon: Icon(
        result.hasSuccess ? Icons.check_circle_outline : Icons.error_outline,
        size: 32,
        color: result.hasSuccess
            ? theme.colorScheme.primary
            : theme.colorScheme.error,
      ),
      title: Text(loc.importResultTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(summary),
            if (result.hasUnresolvedNames) ...[
              const SizedBox(height: 16),
              InfoBanner(
                icon: Icons.search_off,
                color: warningColor,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      loc.importResultUnresolvedHeader(
                        result.unresolvedNames.length,
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: warningColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onLongPress: () => _copyUnresolvedToClipboard(context),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 150),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: result.unresolvedNames
                                .map(
                                  (name) => Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: Text(
                                      name,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            fontStyle: FontStyle.italic,
                                          ),
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      loc.importResultUnresolvedHint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (result.lastError != null) ...[
              const SizedBox(height: 12),
              InfoBanner(
                icon: Icons.error_outline,
                color: theme.colorScheme.error,
                child: Text(
                  loc.describeError(result.lastError),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ],
            if (result.hasSuccess) ...[
              const SizedBox(height: 12),
              InfoBanner(
                icon: Icons.cloud_sync_outlined,
                color: theme.colorScheme.primary,
                child: Text(
                  loc.inatDialogMessage,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (result.hasSuccess) ...[
              FilledButton.icon(
                key: const Key('import_result_enrich_button'),
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.download, size: 18),
                label: Text(loc.inatDialogConfirm),
              ),
              const SizedBox(height: 8),
            ],
            OutlinedButton(
              key: const Key('import_result_close_button'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(loc.importResultClose),
            ),
          ],
        ),
      ],
    );
  }

  void _copyUnresolvedToClipboard(BuildContext context) {
    final text = result.unresolvedNames.join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.loc.importResultCopied),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
