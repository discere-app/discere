import 'package:discere/learning/decks/species_field_presenter.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// The verdict on the create-deck species field, one row per outcome: how
/// many species were found, which lines will be looked up on iNaturalist,
/// and which cannot name a species. A row without lines is left out.
class SpeciesFieldSummary extends StatelessWidget {
  final SpeciesFieldCheck check;

  const SpeciesFieldSummary({required this.check, super.key});

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    final colorScheme = Theme.of(context).colorScheme;
    const presenter = SpeciesFieldPresenter();

    String listed(List<String> names) {
      final (:shown, :hiddenCount) = presenter.abbreviate(names);
      final joined = shown.join(', ');
      return hiddenCount == 0
          ? joined
          : loc.createSpeciesCheckMoreNames(joined, hiddenCount);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (check.foundCount > 0)
          _SummaryRow(
            key: const Key('create_deck_species_found'),
            icon: Icons.check_circle_outline,
            color: colorScheme.primary,
            text: loc.createSpeciesCheckFound(check.foundCount),
          ),
        if (check.notFoundLocally.isNotEmpty)
          _SummaryRow(
            key: const Key('create_deck_species_not_found_locally'),
            icon: Icons.help_outline,
            color: Colors.orange.shade800,
            text: loc.createSpeciesCheckNotFoundLocally(
              check.notFoundLocally.length,
              listed(check.notFoundLocally),
            ),
          ),
        if (check.notSpeciesNames.isNotEmpty)
          _SummaryRow(
            key: const Key('create_deck_species_not_species_name'),
            icon: Icons.highlight_off,
            color: colorScheme.error,
            text: loc.createSpeciesCheckNotSpeciesName(
              check.notSpeciesNames.length,
              listed(check.notSpeciesNames),
            ),
          ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _SummaryRow({
    required this.icon,
    required this.color,
    required this.text,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          AppSpacing.widthS8,
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
