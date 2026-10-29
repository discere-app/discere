import 'package:discere/learning/model/subdeck.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/ui/section_card.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Edit-deck section with one switch per subdeck: only species of the
/// subdecks switched on are cards. Part of the draft like every other
/// field — a switch only takes effect when the deck is saved.
class SubdeckSection extends StatelessWidget {
  final List<Subdeck> subdecks;
  final Set<String> activeSubdeckIds;

  /// Species of the draft in each subdeck.
  final Map<String, int> speciesCounts;

  /// Whether a subdeck that is on may be switched off
  /// (`SubdeckMembership.canSwitchOff`).
  final bool Function(String subdeckId) canSwitchOff;

  final void Function(String subdeckId, bool active) onChanged;

  /// Coach-mark target for `EditDeckTutorial`, on the section title like
  /// the learning settings' one.
  final GlobalKey? titleKey;

  const SubdeckSection({
    required this.subdecks,
    required this.activeSubdeckIds,
    required this.speciesCounts,
    required this.canSwitchOff,
    required this.onChanged,
    this.titleKey,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KeyedSubtree(
          key: titleKey,
          child: Text(
            context.loc.editDeckSubdecksTitle,
            style: theme.textTheme.titleSmall,
          ),
        ),
        AppSpacing.heightS8,
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s16,
                  AppSpacing.s16,
                  AppSpacing.s16,
                  AppSpacing.s8,
                ),
                child: Text(
                  context.loc.editDeckSubdecksDescription,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (final subdeck in subdecks) _switchFor(context, subdeck),
            ],
          ),
        ),
      ],
    );
  }

  Widget _switchFor(BuildContext context, Subdeck subdeck) {
    final active = activeSubdeckIds.contains(subdeck.id);
    final enabled = !active || canSwitchOff(subdeck.id);
    return SwitchListTile(
      key: Key('edit_deck_subdeck_switch_${subdeck.id}'),
      title: Text(subdeck.name),
      subtitle: Text(
        context.loc.subdeckSpeciesCount(speciesCounts[subdeck.id] ?? 0),
      ),
      value: active,
      onChanged: enabled ? (value) => onChanged(subdeck.id, value) : null,
    );
  }
}
