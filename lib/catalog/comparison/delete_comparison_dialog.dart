import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

/// Asks whether to delete the comparison list [name]. Resolves to `true` only
/// on confirmation.
Future<bool> showDeleteComparisonDialog(
  BuildContext context,
  String name,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.loc.comparisonDeleteTitle),
      content: Text(context.loc.comparisonDeleteMessage(name)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.loc.commonCancel),
        ),
        TextButton(
          key: const Key('comparison_delete_confirm_button'),
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          child: Text(context.loc.comparisonDelete),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
