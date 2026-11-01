import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// App bar of EditDeckPage: back, title and the save button, which shows a
/// spinner while [isSaving] and is disabled without [onSave].
class EditDeckAppBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback onBack;
  final VoidCallback? onSave;
  final bool isSaving;

  const EditDeckAppBar({
    required this.onBack,
    required this.onSave,
    required this.isSaving,
    super.key,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: onBack,
      ),
      title: Text(context.loc.editDeckTitle),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: AppSpacing.elementSpacing),
          child: TextButton.icon(
            key: const Key('edit_deck_save_button'),
            onPressed: onSave,
            icon: isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check, size: 18),
            label: Text(context.loc.editSaveButton),
          ),
        ),
      ],
    );
  }
}
