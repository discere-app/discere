import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// The watchlist's taxonomic-class filter: one tab per class present in the
/// list, preceded by an "all species" tab.
///
/// "All species" is [selectedClassName] being null rather than a sentinel
/// class name, so the absence of a filter cannot collide with a real class and
/// needs no magic string shared between this widget and the page.
class WatchlistCategoryTabs extends StatelessWidget {
  final List<String> classNames;
  final String? selectedClassName;
  final ValueChanged<String?> onSelected;

  const WatchlistCategoryTabs({
    super.key,
    required this.classNames,
    required this.selectedClassName,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenPadding,
        vertical: AppSpacing.elementSpacing,
      ),
      child: Row(
        children: [
          _tab(context, label: context.loc.watchlistAllSpecies, className: null),
          for (final className in classNames)
            _tab(context, label: className, className: className),
        ],
      ),
    );
  }

  Widget _tab(
    BuildContext context, {
    required String label,
    required String? className,
  }) {
    final theme = Theme.of(context);
    final isSelected = className == selectedClassName;

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.groupSpacing),
      child: InkWell(
        onTap: () => onSelected(className),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
            AppSpacing.heightS8,
            Container(
              height: 2,
              width: 24,
              decoration: BoxDecoration(
                color: isSelected
                    ? theme.colorScheme.primary
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
