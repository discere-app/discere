import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/ui/info_banner.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:discere/theme/ocean_theme/ocean_colors.dart';
import 'package:flutter/material.dart';

/// The bar under the online-deck list: what importing the current selection
/// would pull in, and the button that does it.
class ImportSelectionBar extends StatelessWidget {
  /// Warned about above this many species, because importing that many at
  /// once means a long enrichment run before the decks are usable.
  static const manySpeciesWarningThreshold = 60;

  final int selectedDeckCount;
  final int selectedSpeciesCount;
  final bool isImporting;

  /// Null while an import runs or nothing is selected.
  final VoidCallback? onImport;

  const ImportSelectionBar({
    super.key,
    required this.selectedDeckCount,
    required this.selectedSpeciesCount,
    required this.isImporting,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Only for a multi-deck selection: one large deck is a deliberate choice,
    // several adding up to the same total is easy to do by accident.
    final warnAboutSize =
        selectedDeckCount > 1 &&
        selectedSpeciesCount > manySpeciesWarningThreshold;

    return Padding(
      padding: AppSpacing.screenPaddingAll,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (warnAboutSize) ...[
            InfoBanner(
              icon: Icons.info_outline,
              color: OceanColors.primaryBlue,
              child: Text(
                context.loc.importOnlineManySpeciesHint(selectedSpeciesCount),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            AppSpacing.heightS8,
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              key: const ValueKey('import-online-button'),
              onPressed: onImport,
              icon: isImporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
              label: Text(context.loc.importSelectedButton(selectedDeckCount)),
            ),
          ),
        ],
      ),
    );
  }
}
