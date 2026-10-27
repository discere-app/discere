import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

/// Asks whether to delete the deck being edited. Resolves to `true` only on
/// confirmation.
Future<bool> showDeleteDeckDialog(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.loc.deleteDeckConfirmationTitle),
      content: Text(context.loc.deleteDeckConfirmationMessage),
      actions: [
        TextButton(
          key: const Key('edit_deck_delete_cancel_button'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.loc.commonCancel),
        ),
        TextButton(
          key: const Key('edit_deck_delete_confirm_button'),
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          child: Text(context.loc.deleteDeckConfirmButton),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
