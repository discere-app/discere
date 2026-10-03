import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/ui/section_card.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// The decks this species is part of, by name.
class SpeciesDecksSection extends StatelessWidget {
  final List<String> deckNames;

  const SpeciesDecksSection({super.key, required this.deckNames});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SectionCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.loc.speciesDetailDecksTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.s8),
            Wrap(
              spacing: AppSpacing.s16,
              runSpacing: AppSpacing.s8,
              children: deckNames
                  .map((name) => _DeckNameLabel(name: name))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeckNameLabel extends StatelessWidget {
  final String name;

  const _DeckNameLabel({required this.name});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.style_outlined,
          size: 18,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.s8),
        Text(
          name,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
