import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/learning/service/deck_import_service.dart';
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
              Text(
                loc.importResultUnresolvedHeader(result.unresolvedNames.length),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.orange.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onLongPress: () => _copyUnresolvedToClipboard(context),
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 150),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: result.unresolvedNames
                          .map(
                            (name) => Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                name,
                                style: theme.textTheme.bodySmall?.copyWith(
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
            if (result.lastError != null) ...[
              const SizedBox(height: 12),
              Text(
                result.lastError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            if (result.hasSuccess) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 4),
              Text(loc.inatDialogMessage, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('import_result_close_button'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(loc.importResultClose),
        ),
        if (result.hasSuccess)
          FilledButton.icon(
            key: const Key('import_result_enrich_button'),
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.download, size: 18),
            label: Text(loc.inatDialogConfirm),
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
