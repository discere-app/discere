import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

/// Full-width button on the edit page that deletes the deck, after
/// confirmation (`showDeleteDeckDialog`). Disabled while [onPressed] is null.
class DeleteDeckButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const DeleteDeckButton({required this.onPressed, super.key});

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        key: const Key('edit_deck_delete_button'),
        onPressed: onPressed,
        icon: const Icon(Icons.delete_outline, size: 18),
        label: Text(context.loc.editDeckDeleteButton),
        style: OutlinedButton.styleFrom(
          foregroundColor: error,
          side: BorderSide(color: error),
        ),
      ),
    );
  }
}
