import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

/// Asks whether to leave the edit page without saving. Resolves to `true`
/// only when the user chooses to discard the changes.
Future<bool> showDiscardChangesDialog(BuildContext context) async {
  final shouldDiscard = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.loc.editDeckDiscardTitle),
      content: Text(context.loc.editDeckDiscardMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.loc.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(context.loc.editDeckDiscardConfirm),
        ),
      ],
    ),
  );
  return shouldDiscard ?? false;
}
