import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Chip showing the language a taxon's names are displayed in, opening a
/// menu to look at them in another one.
///
/// It only reports the pick through [onSelected]; what the choice applies
/// to and how long it lasts is the caller's state. [selectableLanguages]
/// comes from `selectableDisplayLanguages`, so the menu offers the same
/// languages wherever the chip appears.
class DisplayLanguageSelector extends StatelessWidget {
  final Language language;
  final List<Language> selectableLanguages;
  final ValueChanged<Language> onSelected;

  const DisplayLanguageSelector({
    super.key,
    required this.language,
    required this.selectableLanguages,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.9),
      shape: const StadiumBorder(),
      elevation: 1,
      child: PopupMenuButton<Language>(
        tooltip: context.loc.commonLanguageSelectorTooltip,
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: onSelected,
        itemBuilder: (context) => [
          for (final selectable in selectableLanguages)
            _buildMenuItem(context, selectable),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s12,
            vertical: 6,
          ),
          child: Text(
            language.name.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 0.4,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  PopupMenuItem<Language> _buildMenuItem(
    BuildContext context,
    Language selectable,
  ) {
    return PopupMenuItem<Language>(
      value: selectable,
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: selectable == language
                ? const Icon(Icons.check, size: 18)
                : null,
          ),
          AppSpacing.widthS8,
          Text(context.loc.commonLanguages(selectable.name)),
        ],
      ),
    );
  }
}
