import 'package:discere/learning/decks/deck_form_fields.dart';
import 'package:discere/shared/extensions/app_exception_localization.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Name, description and cover image of EditDeckPage. A picked image is stored
/// here, with a failure reported to the user, so the page only hears of a cover
/// it can keep.
class EditDeckBasicsFields extends StatelessWidget {
  static final _log = Logger.forType(EditDeckBasicsFields);

  final TextEditingController nameController;
  final TextEditingController descriptionController;
  final String? coverImagePath;
  final ValueChanged<String?> onCoverImageChanged;

  const EditDeckBasicsFields({
    required this.nameController,
    required this.descriptionController,
    required this.coverImagePath,
    required this.onCoverImageChanged,
    super.key,
  });

  Future<void> _handleImageSelected(BuildContext context, String? path) async {
    if (path == null) {
      onCoverImageChanged(null);
      return;
    }
    try {
      final savedPath = await context.read<ImageService>().saveCoverImage(path);
      if (context.mounted) onCoverImageChanged(savedPath);
    } catch (e, stackTrace) {
      _log.warn('Cover image save failed', error: e, stackTrace: stackTrace);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.loc.errorSaveImage(context.loc.describeError(e)),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DeckNameField(
          key: const Key('edit_deck_name_field'),
          controller: nameController,
        ),
        const SizedBox(height: AppSpacing.s20),
        DeckDescriptionField(
          key: const Key('edit_deck_description_field'),
          controller: descriptionController,
        ),
        AppSpacing.heightS24,
        DeckCoverImageField(
          currentImagePath: coverImagePath,
          onImageSelected: (path) => _handleImageSelected(context, path),
        ),
      ],
    );
  }
}
