import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/ui/image_picker.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Shared form sections for the create- and edit-deck pages. Both pages
/// edit the same deck fields, so they render them through these widgets —
/// one place decides how a deck form field looks.

class DeckFormSectionLabel extends StatelessWidget {
  final String label;

  const DeckFormSectionLabel({required this.label, super.key});

  @override
  Widget build(BuildContext context) {
    return Text(label, style: Theme.of(context).textTheme.titleSmall);
  }
}

/// Deck-name input with its section label. Pass the page-specific [key] so
/// widget tests can target the field per page.
class DeckNameSection extends StatelessWidget {
  final TextEditingController controller;

  const DeckNameSection({required this.controller, super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DeckFormSectionLabel(label: context.loc.createDeckNameLabel),
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

class DeckDescriptionSection extends StatelessWidget {
  final TextEditingController controller;

  const DeckDescriptionSection({required this.controller, super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DeckFormSectionLabel(label: context.loc.createDescriptionLabel),
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

class DeckCoverImageSection extends StatelessWidget {
  final String? currentImagePath;
  final Future<void> Function(String? path) onImageSelected;

  const DeckCoverImageSection({
    required this.currentImagePath,
    required this.onImageSelected,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DeckFormSectionLabel(label: context.loc.createCoverImageLabel),
        AppSpacing.heightS8,
        ImagePicker(
          currentImagePath: currentImagePath,
          onImageSelected: onImageSelected,
        ),
      ],
    );
  }
}

class DeckLanguageSection extends StatelessWidget {
  final Language value;
  final ValueChanged<Language> onChanged;

  const DeckLanguageSection({
    required this.value,
    required this.onChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DeckFormSectionLabel(label: context.loc.createDeckLanguageLabel),
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
