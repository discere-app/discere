import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/ui/image_picker.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Shared form fields for the create- and edit-deck pages. Both pages
/// edit the same deck fields, so they render them through these widgets —
/// one place decides how a deck form field looks.

class DeckFormFieldLabel extends StatelessWidget {
  final String label;

  const DeckFormFieldLabel({required this.label, super.key});

  @override
  Widget build(BuildContext context) {
    return Text(label, style: Theme.of(context).textTheme.titleSmall);
  }
}

/// Deck-name input with its section label. Pass the page-specific [key] so
/// widget tests can target the field per page.
class DeckNameField extends StatelessWidget {
  final TextEditingController controller;

  const DeckNameField({required this.controller, super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DeckFormFieldLabel(label: context.loc.createDeckNameLabel),
        AppSpacing.heightS8,
        TextField(
          controller: controller,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: context.loc.createDeckNameHint,
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}

class DeckDescriptionField extends StatelessWidget {
  final TextEditingController controller;

  const DeckDescriptionField({required this.controller, super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DeckFormFieldLabel(label: context.loc.createDescriptionLabel),
        AppSpacing.heightS8,
        TextField(
          controller: controller,
          minLines: 3,
          maxLines: 6,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: context.loc.createDescriptionHint,
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}

class DeckCoverImageField extends StatelessWidget {
  final String? currentImagePath;
  final Future<void> Function(String? path) onImageSelected;

  const DeckCoverImageField({
    required this.currentImagePath,
    required this.onImageSelected,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DeckFormFieldLabel(label: context.loc.createCoverImageLabel),
        AppSpacing.heightS8,
        ImagePicker(
          currentImagePath: currentImagePath,
          onImageSelected: onImageSelected,
        ),
      ],
    );
  }
}

class DeckLanguageField extends StatelessWidget {
  final Language value;
  final ValueChanged<Language> onChanged;

  const DeckLanguageField({
    required this.value,
    required this.onChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DeckFormFieldLabel(label: context.loc.createDeckLanguageLabel),
        AppSpacing.heightS8,
        DropdownButtonFormField<Language>(
          isExpanded: true,
          initialValue: value,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items: Language.values.map((lang) {
            return DropdownMenuItem<Language>(
              value: lang,
              child: Text(context.loc.commonLanguages(lang.name)),
            );
          }).toList(),
          onChanged: (Language? newValue) {
            if (newValue != null) onChanged(newValue);
          },
        ),
      ],
    );
  }
}
